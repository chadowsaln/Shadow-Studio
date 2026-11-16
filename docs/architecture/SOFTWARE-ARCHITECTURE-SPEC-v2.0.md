# Shadow Studio — Software Architecture Specification v2.0

| الحقل | القيمة |
| --- | --- |
| Document ID | `SS-ARCH-002` |
| Version | `2.0` |
| Status | **Approved baseline** — يستبدل تفكيك الأنظمة في v1.0 |
| Scope | MVP: Agent Runtime + Editing Core + Native Media Engine، محلي بالكامل |
| Audience | مهندسو Flutter/Dart، مهندسو C++/Media، مهندسو الأدوات والوكلاء |
| Supersedes | `SS-ARCH-001` v1.0 — **تفكيك الأنظمة فقط**؛ عقد المحرك (الملحق أ/هـ) يُورَّث كما هو |
| Inherits | RenderGraph + سجل المؤثرات + المخطط الحقلي (`rendergraph.schema.json`) |

**القرارات المثبَّتة (غير قابلة لإعادة الفتح في هذا الإصدار):** Desktop-first، **لا Backend ولا خادم HTTP**، تنفيذ محلي للمعالجة، وكيل مستقل مع بوابة موافقات، مزودون متعددون، تحرير غير مُدمِّر، توزيع مجاني، SQLite + ملف مشروع محلي.

**قاعدة الوثيقة:** specification لا implementation. لا كود مصدري إلا **توقيعات واجهات** و**مخطط DDL**، لأنها الحدود الملزمة بين الوحدات. أي خروج يحتاج Decision Record.

---

## 0. اصطلاحات

| المصطلح | المعنى الدقيق |
| --- | --- |
| **Module** | وحدة قابلة للنشر داخل التطبيق (Dart package أو native library) بحدود معلنة |
| **Port** | واجهة مجردة يملكها المستهلك (consumer-owned) |
| **Adapter** | تنفيذ تقني لـ Port (OpenAI، Gemini، MLT، FFmpeg، Keyring…) |
| **Tick** | وحدة الزمن الداخلية = 1/1,000,000 ثانية، عدد صحيح |
| **Document** | حالة المشروع الكاملة في الذاكرة (immutable snapshot) |
| **Revision** | عدّاد أحادي التزايد يزداد مع كل `EditTransaction` مُثبَّتة |
| **Agent Task** | طلب مستخدم واحد، له ميزانية وحدود تنفيذ وحالة نهائية |
| **Tool Call** | استدعاء أداة مسجّلة من الوكيل بمدخلات JSON تحقق مخططها |
| **Approval** | قرار مستخدم صريح لعملية Restricted/Dangerous، صالح لاستدعاء واحد فقط |
| **Risk Class** | تصنيف الأداة: Safe / Restricted / Dangerous |

**اصطلاح الزمن:** كل المواضع والمدد أعداد صحيحة بوحدة Tick على حدود الوحدات، ولا `double` زمني. تحويل tick→frame: `floor(tick × fps_num / (1e6 × fps_den))`، والعكس `ceil(frame × 1e6 × fps_den / fps_num)`؛ التقريب على حدود الإطارات يحدث في Editing Core لا في الواجهة ولا في المحرك.

---

## 1. نظرة عامة وأهداف الجودة

### 1.1 المفهوم

Shadow Studio ليس محرر فيديو أضيف إليه شات. هو **بيئة تنفيذ محلية لوكيل** يمتلك: تخطيطاً، أدوات تحرير حقيقية، سياق مشروع، وصلاحيات مضبوطة. الواجهة تعرض **الخطة والحالة والنتائج**، لا سلسلة التفكير الداخلية للنموذج.

```
Flutter Desktop (chat · timeline · preview · inspector · assets)
        │  Dart interfaces (in-process)
Agent Runtime ── Provider Gateway ── HTTP/SSE إلى مزودي AI
        │  Tool Registry (عقود أدوات + صلاحيات)
Permission Engine (بوابة إلزامية لكل أثر جانبي)
        │
Editing Core (document · commands · undo · RenderGraph)
        │  framed MessagePack على stdio
Native Media Worker (C++: MLT + FFmpeg) ──> shared memory ──> Flutter texture (FFI)
        │
Local Persistence (SQLite + ملف مشروع + cache + keyring)
```

### 1.2 أهداف الجودة

| # | الهدف | السيناريو | الهدف القابل للقياس | كيف نتحقق |
| --- | --- | --- | --- | --- |
| QG-1 | **Non-destructiveness** | قصّ 500 مقطع ثم تصدير | 0 بايت معدّل في أي ملف أصلي | hash قبل/بعد لكل أصل في الاختبار |
| QG-2 | **Responsiveness** | سحب playhead في timeline فيه 300 clip | 60 fps للواجهة، scrub ≤ 120 ms p95 | Flutter frame timings + probe على `frameAt` |
| QG-3 | **Crash isolation** | انهيار MLT/FFmpeg أثناء render | 0 crash للتطبيق، إعادة تشغيل العامل ≤ 3 s، المهمة تفشل بوضوح | حقن `SIGSEGV` في العامل + إعادة تشغيل تلقائي |
| QG-4 | **Determinism** | نفس المشروع + نفس preset مرتين | نفس عدد الإطارات ونفس `framemd5` للصوت والصورة | مقارنة ffprobe + framemd5 |
| QG-5 | **Local-only by default** | تشغيل بلا مفاتيح AI | 0 طلب شبكي أثناء الفتح والتحرير والتصدير | تشغيل في sandbox بلا شبكة |
| QG-6 | **Autonomy with consent** | حذف أصل أو كتابة فوق ملف مستخدم | 0 عملية Dangerous بلا موافقة صريحة | اختبارات أدوات + audit log |
| QG-7 | **Startup** | فتح مشروع 200 clip | نافذة تفاعلية ≤ 2.5 s، timeline جاهز ≤ 4 s | قياس cold start في CI |
| QG-8 | **Memory** | مشروع 4 ساعات، 6 مسارات | UI < 800 MB، عامل الوسائط < 1.5 GB | قياس دوري + budget في CI |
| QG-9 | **Recoverability** | انقطاع كهرباء أثناء render | 0 مهمة ضائعة صامتة، آخر revision سليمة، الوكيل يستأنف من checkpoint | قطع العملية في منتصف المراحل |
| QG-10 | **Testability** | اختبار Editing Core والوكيل بلا GPU ولا شبكة | مجموعة وحدة < 5 s | CI بلا وسائط حقيقية عبر fakes |
| QG-11 | **Cost control** | مهمة طويلة بمزود مدفوع | 0 استدعاء يتجاوز ميزانية المهمة | Gateway يعدّ ويوقف، اختبار بمزود وهمي |

### 1.3 خارج النطاق

Cloud rendering، تعاون متعدد المستخدمين، mobile، تعدد نوافذ، توزيع تجاري، خادم مركزي، أي API شبكي عام، وكل ما ذُكر في «خارج نطاق MVP».

---

## 2. الوحدات والحدود

### 2.1 شجرة المستودع

```
shadow-studio/
├── apps/desktop/lib/{app,core,features/{assistant,projects,media_library,timeline,preview,inspector,export,settings},main.dart}
├── packages/
│   ├── agent_runtime/{controller,execution,planner,context,memory,scheduler,recovery}
│   ├── provider_gateway/{interfaces,adapters/{openai,gemini,anthropic,openrouter},routing,streaming}
│   ├── tool_system/{registry,executor,schemas,tools/{filesystem,analysis,editing,audio,rendering}}
│   ├── editing_core/{project,timeline,tracks,clips,effects,transitions,commands,undo_redo}
│   ├── media_core/{metadata,thumbnails,proxies,codecs,export}   # Dart client للعامل
│   ├── environment/{detection,capabilities,adaptive_profiles}
│   ├── permissions/{policies,sandbox,approvals,audit}
│   └── local_storage/{database,repositories,migrations,project_files}
├── native/{cpp/{media_engine,mlt_adapter,ffmpeg_adapter,preview},include}
├── contracts/{agent,tools,editing,providers,media}
├── docs/{architecture,api,decisions}
└── scripts/
```

**قاعدة عملية:** ابدأ بـ `apps/desktop` + `agent_runtime` + `tool_system` + `editing_core` + `native` حزمًا ذات حدود واضحة؛ لا تُحوّل كل مجلد إلى package مستقلاً في اليوم الأول.

### 2.2 جدول الوحدات والاعتماديات

العمود الأخير هو قاعدة التبعية القابلة للفحص آلياً: وحدة لا تستورد غير ما هو مذكور.

| # | الوحدة | المسؤولية في سطر | يُسمح لها بالاعتماد على |
| --- | --- | --- | --- |
| 1 | `desktop/app` | shell، routing، theming، DI، ملكية النوافذ | `permissions`, `agent_runtime`, `editing_core`, `local_storage` + حزم الواجهة الفرعية داخل نفس الوحدة |
| 2 | `agent_runtime` | دورة حياة المهمة، التخطيط، التنفيذ، الاستئناف | `provider_gateway`, `tool_system`, `editing_core` (قراءة), `local_storage`, `permissions` |
| 3 | `provider_gateway` | تحويل طلبات/ردود المزودين إلى صيغة موحدة، بث، ميزانيات | `contracts/providers` فقط |
| 4 | `context_engine` | تجميع سياق المشروع داخل ميزانية tokens بلقطة قابلة للتكرار | `editing_core` (قراءة), `local_storage`, `contracts/agent` |
| 5 | `tool_system` | سجل الأدوات، تحقق المخططات، التنفيذ، النتائج | `editing_core`, `permissions`, `media_core`, `local_storage` |
| 6 | `environment` | كشف OS/CPU/RAM/GPU/codecs/disk → Adaptive Profile | stdlib + native FFI للنظام |
| 7 | `permissions` | تصنيف المخاطر، sandbox المسارات، الموافقات، audit | `local_storage`, `contracts/tools` |
| 8 | `editing_core` | document، commands، undo، revisions، اشتقاق RenderGraph | `local_storage`, `contracts/editing` |
| 9 | `media_core` (Dart) | عميل العامل: probe، proxy، preview، render، إلغاء | `contracts/media` + FFI عرض الإطارات فقط |
| 10 | `native/media_worker` (C++) | فك ترميز، تركيب، ترميز، mux عبر MLT/FFmpeg | libmlt, libav* فقط |
| 11 | `local_storage` | SQLite، ملف المشروع، cache، keyring، migrations | stdlib + SQLite + keyring |

**قاعدة التبعية:** `editing_core` لا يعرف الوكيل ولا المزود؛ `agent_runtime` لا يعرف MLT ولا FFmpeg؛ `native` لا يعرف المشروع؛ والواجهة لا تتحدث إلى native مباشرة. الاتجاه مسموح فقط نزولاً في الجدول عند وجود سطر اعتماد.

### 2.3 قرارات التفكيك

#### V2-D1 — لا Backend ولا خادم HTTP

**القرار:** الوكيل والتحرير والتخزين كلها داخل تطبيق سطح المكتب. لا FastAPI، لا PostgreSQL، لا خادم loopback، ولا WebSocket محلي؛ التواصل بين الوحدات استدعاء Dart مباشر، وإلى العامل pipe على stdio.
**المرفوض:** (أ) خادم HTTP محلي — يضيف سطح هجوم ومنفذاً وحلقة IPC بلا فائدة، ويكسر «بلا Backend»؛ (ب) خادم مركزي — يناقض محلية الملفات؛ (ج) gRPC — يعيد نفس التعقيد دون حاجة.

#### V2-D2 — الوحدات الثقيلة في عامل منفصل

**القرار:** كل عمل MLT/FFmpeg داخل عملية `shadow_media_worker` مستقلة، تُدار عبر رسائل MessagePack مؤطّرة على stdio. الإطارات تنتقل عبر **shared memory** وتُعرض كـ texture عبر FFI. Dart لا يملك مؤشرات كوديك ولا يشغّل فك ترميز.
**المرفوض:** (أ) FFI داخل العملية الرئيسية — أي segfault في libmlt يقتل التطبيق (يناقض QG-3)، والإلغاء يستحيل مع مكتبات لا تدعم abort؛ (ب) عامل داخل isolate — لا يعزل crash أصلي؛ (ج) HTTP للعامل — يعيد سطح الهجوم.

#### V2-D3 — الأدوات هي السطح الوحيد للقدرات

**القرار:** الوكيل لا يستطيع تنفيذ أوامر نظام، ولا استدعاء native، ولا فتح مسار خارج workspace إلا عبر أداة مسجّلة وتحقق مخططها وبوابة الصلاحيات. لا أداة shell عامة في v1.
**المرفوض:** أداة shell موثوقة أو «bash sandboxed» — تصعيد امتيازات وكسر النموذج الأمني؛ أداة `run_code` — لا يمكن ضبط أثرها.

#### V2-D4 — السياق لقطة قابلة للتكرار

**القرار:** كل دورة تفكير تبني `ContextSnapshot` يشمل `project_revision` و`workspace_root` و`context_hash`؛ يُسجَّل مع كل Tool Call. إعادة تشغيل مهمة من checkpoint تستخدم نفس اللقطة أو تفشل بوضوح.
**المرفوض:** سياق حي متغيّر — يجعل تصحيح السلوك مستحيلاً ويخالف حتمية الأدوات.

---

## 3. نموذج التنفيذ والتزامن

| الموضوع | القرار |
| --- | --- |
| خيوط Dart | واجهة Flutter على main isolate؛ الوكيل على isolate منفصل مع `SendPort`؛ لا عمل شبكي أو قراءة ملفات كبيرة على main |
| العامل | عملية واحدة افتراضياً؛ مهمة render ثقيلة قد تُشغّل عاملاً ثانياً حتى سقف `min(2, cores/2)` |
| التدفق | الوكيل يدفع `AgentEvent` (خطة/خطوة/أداة/نتيجة/موافقة/خطأ/تقدّم) إلى الواجهة؛ الواجهة لا تسأل عن الحالة دورياً |
| الإلغاء | `CancellationToken` يمرَّق من الواجهة → الوكيل → الأداة → العامل؛ إلغاء الوكيل يوقف الاستدعاء المقبل ولا يقطع كتابة ذرّية جارية |
| Backpressure | قناة أحداث بسعة محدودة؛ عند الامتلاء يُسقط `progress` الأقدم فقط، ولا تُسقط `approval`/`error`/`done` |
| الحجب | لا call متزامن في مسار الواجهة؛ كل ما يتجاوز 16 ms يذهب إلى isolate أو العامل |
| الذاكرة | إطار preview ≤ 8 MB (1080p RGBA) لكل جلسة؛ أكثر من جلسة معاينة واحدة ممنوع في v1 |

---

## 4. Agent Runtime

### 4.1 المكونات

| Module | المسؤولية |
| --- | --- |
| `AgentController` | دورة حياة المهمة: create → plan → act → finish/cancel/fail |
| `ExecutionLoop` | دورة التفكير/الأداة/الملاحظة وميزانياتها |
| `Planner` | تقسيم الطلب إلى خطوات قابلة للتحقق |
| `ToolExecutor` | تحقق → صلاحية → تنفيذ → تحقق النتيجة → audit |
| `ContextManager` | بناء `ContextSnapshot` وتقليمه |
| `ProviderRouter` | اختيار المزود/الموديل، fallback، ميزانية التكلفة |
| `MemoryManager` | ملخصات الجلسة والمهام السابقة (محلياً) |
| `TaskScheduler` | أولوية المهام، مهمة نشطة واحدة v1 |
| `PermissionManager` | طلب/تسجيل الموافقات وربطها بالاستدعاء |
| `RecoveryManager` | checkpoints واستئناف بعد تعطل |

### 4.2 دورة التنفيذ

```
request → inspect environment/context → plan → call provider
   → tool_call? → permission → execute → observe → evaluate
   → (done | retry | replan | fail)
```

### 4.3 حدود التنفيذ (ملزمة، لا إعدادات مستخدم في v1)

| الحد | القيمة | السلوك عند التجاوز |
| --- | --- | --- |
| حد استدعاءات الأدوات لكل مهمة | 40 | إيقاف المهمة بـ `AGENT_BUDGET_EXCEEDED`، مع checkpoint |
| الزمن الكلي للمهمة | 10 دقائق | إلغاء تعاوني ثم `AGENT_TIMEOUT` |
| إعادة المحاولة لكل أداة | 3 | فشل الأداة يُعاد للوكيل كملاحظة |
| ميزانية tokens للمدخلات | 60k لكل مهمة | Gateway يرفض ويطلب تلخيصاً |
| كشف الحلقة | 3 تكرارات متتالية لنفس (أداة + مدخلات) | `AGENT_LOOP_DETECTED` |
| checkpoint | 1 بعد كل Tool Call | استئناف من آخر checkpoint |
| الموافقات المعلقة | 1 في كل لحظة | طلب جديد يستبدل القديم بعد رفضه صراحةً |

#### V2-D5 — الحدود في المحرك لا في النموذج

**القرار:** الميزانيات تُفرض في `ExecutionLoop`/`Gateway`، ولا تُترك لتعليمات prompt. النموذج يستطيع إنهاء المهمة مبكرًا، ولا يستطيع تجاوز حد.
**المرفوض:** تعليمات prompt فقط — تُخترق بسهولة وبتغيير مزود؛ أو حدود بالزمن فقط — لا تمنع حلقة سريعة مكلفة.

### 4.4 حالة المهمة

```
queued → planning → acting → awaiting_approval → acting → succeeded
                                  │                    └→ failed
                                  └→ cancelled          └→ cancelled
```

الحالات النهائية `succeeded | failed | cancelled` لا تقبل أحداثاً بعدها؛ أي حدث متأخر يُسجَّل ويُهمل. `awaiting_approval` له مهلة 10 دقائق ثم يُعدّ رفضاً (`PERM_APPROVAL_TIMEOUT`).

---

## 5. Provider Gateway

### 5.1 الواجهة

```dart
abstract interface class AIProvider {
  String get id;
  Set<ProviderFeature> get features;
  Future<List<AIModel>> getModels({required CancellationToken cancel});
  Stream<AIStreamEvent> stream({
    required AIRequest request,
    required CancellationToken cancel,
  });
}

class AIRequest {
  final String model;
  final List<AIMessage> messages;
  final List<AIToolDefinition> tools;
  final double temperature;
  final int maxOutputTokens;
  final RequestBudget budget;
}
```

### 5.2 خريطة القدرات

| القدرة | OpenAI | Gemini | Anthropic | OpenRouter | سلوك الغياب |
| --- | --- | --- | --- | --- | --- |
| Tool calling | نعم | نعم | نعم | حسب الموديل | أداة تُخفى من الطلب، لا تُرسل |
| Streaming | نعم | نعم | نعم | نعم | انتظار كامل الرد |
| Vision | حسب الموديل | حسب الموديل | حسب الموديل | حسب الموديل | `analyze_video` يرفض `PROVIDER_UNSUPPORTED` |
| JSON mode | نعم | نعم | جزئي | حسب الموديل | مخطط صارم في prompt + تحقق محلي |
| Prompt caching | نعم | نعم | نعم | لا | لا أثر وظيفي |

### 5.3 قواعد ملزمة

1. كل Adapter يحوّل `AIToolDefinition` (JSON Schema جزئي) إلى صيغة المزود ويعيد `AIToolCall` موحّداً؛ لا يتعرف الوكيل على صيغة مزود.
2. **المفاتيح** في keyring النظام فقط؛ لا SQLite، لا ملفات مشروع، لا logs، لا تصدير تشخيصي.
3. الميزانية تُفرض قبل الطلب (tokens/تكلفة) وبعده (استهلاك فعلي)؛ تجاوزها = `PROVIDER_BUDGET_EXCEEDED` بلا إعادة محاولة.
4. `fallback` مسموح فقط عند فشل شبكي/5xx وبعد تسجيل السبب؛ لا fallback عند 401/403/400.
5. **خروج البيانات:** أي إطار أو ملف يُرسل لمزود vision يُعلَن في الواجهة قبل الإرسال، ويُسجَّل `egress` في audit بأسماء الملفات فقط.
6. الإلغاء يوقف القراءة ويحرر الاتصال خلال ≤ 2 s؛ لا يُترك stream مفتوحاً.

#### V2-D6 — لا إعادة إرسال صامتة لمفتاح مرفوض

**القرار:** 401/403 توقف المزود وتطلب إصلاح الإعداد؛ لا تدوير مفاتيح ولا إعادة محاولة.
**المرفوض:** retry مع مزود آخر — يخفي خطأ إعداد ويضاعف التكلفة.

---

## 6. Context Engine

| المصدر | ما يُضمَّن | ما يُستبعد |
| --- | --- | --- |
| المشروع | الاسم، profile، المسارات، عدد المقاطع، revision | snapshot كامل لكل clip |
| التحديد | العنصر المحدد وخصائصه فقط | بقية timeline |
| الأدوات | أسماء + أوصاف مختصرة + schema عند الحاجة | كل المخططات في كل دورة |
| الذاكرة | ملخص الجلسة + آخر 3 نتائج أدوات | نصوص خام طويلة |
| البيئة | profile مختصر (OS، ذاكرة، GPU، codecs) | مسارات نظام كاملة |

**الحد:** `context_hash` يُحسب من اللقطة المرسلة؛ تجاوز 60k tokens يفعّل تقليماً بترتيب معلن (نتائج أدوات قديمة → تفاصيل timeline → ذاكرة) ويُسجَّل `context_trimmed: true`.

---

## 7. Tool System

### 7.1 عقد الأداة

```dart
enum ToolRiskLevel { safe, restricted, dangerous }

abstract interface class AgentTool {
  String get name;
  String get description;
  ToolRiskLevel get riskLevel;
  bool get idempotent;
  Map<String, Object?> get inputSchema; // JSON Schema جزئي، مغلق
  Future<ToolResult> execute(ToolContext context, Map<String, Object?> arguments);
}

class ToolContext {
  final int revision;
  final String workspaceRoot;
  final CancellationToken cancel;
  final ApprovalToken? approval;
  final AuditSink audit;
}
```

### 7.2 خط أنابيب التنفيذ

```
tool_call → schema validate → risk/permission → path validation → execute
          → result validate → audit → return
```

قواعد: (1) مخطط مغلق بلا حقول إضافية؛ (2) معاملات غير صالحة = `TOOL_INVALID_ARGS` بلا تنفيذ؛ (3) الأداة لا تكتب خارج workspace ولا تتبع symlink خارجياً (`PERM_PATH_ESCAPE`)؛ (4) الأداة الآمنة تُنفَّذ تلقائياً؛ (5) نتيجة الأداة محدودة الحجم (≤ 256 KiB) وإلا تُلخَّص مع إشارة `truncated`؛ (6) الأدوات الحتمية لا تعتمد على الوقت أو العشوائية.

#### V2-D7 — الأدوات تغيّر الوثيقة عبر Commands فقط

**القرار:** كل أداة تحرير تنتج `EditTransaction` على `EditingService`؛ لا تعديل مباشر لملفات المشروع ولا للمصادر.
**المرفوض:** كتابة ملفات المشروع مباشرة — تكسر undo/redo وrevisions وتفتح باب عدم الحتمية.

### 7.3 أدوات v1

| الأداة | المخاطر | Idempotent | ملاحظة |
| --- | --- | --- | --- |
| `get_system_info` | safe | نعم | من Environment Profile |
| `inspect_capabilities` | safe | نعم | codecs/محرك/GPU |
| `list_files` | safe | نعم | داخل workspace فقط |
| `scan_media` | safe | نعم | امتدادات + probe سريع |
| `get_metadata` | safe | نعم | من cache الـ probe |
| `analyze_video` | restricted | نعم | يرسل إطارات لمزود vision → إعلان egress |
| `extract_keyframes` | safe | نعم | مشتقات في cache |
| `detect_scenes` | safe | نعم | مشتقات في cache |
| `create_project` | restricted | نعم | إنشاء داخل workspace |
| `open_project` | restricted | نعم | مسار داخل workspace |
| `save_project` | safe | نعم | ذرّي + revision |
| `add_clip` | safe | نعم | يرفض خارج range |
| `trim_clip` | safe | نعم | غير مُدمِّر |
| `split_clip` | safe | نعم | نقطة داخل المقطع |
| `move_clip` | safe | نعم | لا تراكب |
| `remove_clip` | safe | نعم | قابل للـ undo |
| `add_effect` | safe | نعم | مؤثر من السجل |
| `remove_effect` | safe | نعم | قابل للـ undo |
| `add_transition` | safe | نعم | حدود §أ.7 |
| `extract_audio` | safe | نعم | مشتق |
| `mix_audio` | safe | نعم | gain/pan/fades فقط |
| `normalize_audio` | safe | نعم | قياس ثم كسب على المقطع |
| `add_text` | safe | نعم | raster من Core |
| `generate_subtitles` | restricted | لا | يستهلك مزوداً، ينتج Proposal |
| `render_preview` | safe | نعم | جلسة واحدة |
| `get_preview` | safe | نعم | إطار/تدفق |
| `render_video` | restricted | نعم | يحتاج مساحة ≥ 1.5× تقدير |
| `export_project` | dangerous | لا | حزمة مشروع + وسائط، موافقة |

---

## 8. Permission & Safety

| التصنيف | أمثلة | السلوك |
| --- | --- | --- |
| Safe | قص، مؤثر، انتقال، مشتقات داخل cache | تنفيذ تلقائي + audit |
| Restricted | إنشاء/فتح مشروع، تحليل vision، تصدير فيديو | تنفيذ تلقائي داخل workspace؛ موافقة عند الخروج منه أو عند إنفاق AI معلن |
| Dangerous | حذف/استبدال أصل، الكتابة فوق ملف مستخدم، تصدير حزمة | **موافقة صريحة لكل استدعاء** |

### 8.1 قواعد ملزمة

1. **لا يستطيع أي رد من النموذج تغيير السياسة**؛ السياسة في `permissions` فقط، والاستدعاء يحمل فقط `approval_token` أحادي الاستخدام مرتبطاً بـ hash المدخلات.
2. `workspace_root` يُثبَّت عند فتح المشروع؛ كل مسار يُطبَّع (`realpath`) ويُفحص أنه داخل الجذر، وأن أي symlink لا يخرج عنه. الفشل = `PERM_PATH_ESCAPE` بلا تنفيذ.
3. Dangerous بلا موافقة = `PERM_APPROVAL_REQUIRED`؛ الموافقة المنتهية/المعاد استخدامها = `PERM_APPROVAL_INVALID`.
4. عملية واحدة يتم تفعيلها لكل موافقة: لا «موافقة دائمة» في v1.
5. audit log غير قابل للتعديل من التطبيق العادي (ملف append-only + hash chain) ويُصدَّر يدوياً.
6. لا أوامر shell ولا استدعاء process من الوكيل؛ العامل الوحيد المسموح هو `shadow_media_worker` الذي يشغّله التطبيق نفسه.

#### V2-D8 — ثلاثة تصنيفات لا خمسة

**القرار:** Safe/Restricted/Dangerous فقط، والحكم مرتبط بالأداة + المسار + الإنفاق، لا بنص الطلب.
**المرفوض:** تصنيف حسب نية النموذج — غير قابل للتحقق؛ أو «موافقة على الجلسة» — تكسر المبدأ «عملية واحدة، موافقة واحدة».

---

## 9. Editing Core

### 9.1 المسؤوليات

Project/Timeline/Track/Clip operations، effects، transitions، audio mix، undo/redo، revisions، validation، واشتقاق `RenderGraph`.

### 9.2 قواعد

1. **Non-destructive:** لا كتابة في أي أصل؛ كل تعديل صف في الوثيقة + عملية في سجل التعديلات.
2. كل تعديل يمرّ بـ `EditTransaction` ذرّي = revision واحد = خطوة undo واحدة.
3. كل قراءة/كتابة تحمل `expected_revision`؛ عدم التطابق = `EDIT_REVISION_MISMATCH` بلا تطبيق.
4. `Document` غير قابل للتغيير؛ الأوامر دوال خالصة `Document → Document + inverse`.
5. الاشتقاق إلى `RenderGraph` يستخدم **المخطط الحقلي المعياري** (الملحق أ من v1 + الملحق هـ)؛ لا يوجد نوع graph ثانٍ.
6. الحدود الزمنية: كل clip داخل `range`، لا تراكب على نفس المسار، والانتقالات على حدّ مقطعين متجاورين.

### 9.3 التوقيع

```dart
abstract interface class EditingService {
  int get revision;
  Future<ProjectDocument> openProject(String path);
  Future<EditOutcome> apply(EditTransaction transaction, {required int expectedRevision});
  Future<EditOutcome> undo({required int expectedRevision});
  Future<EditOutcome> redo({required int expectedRevision});
  Future<void> save();
  RenderGraph resolveGraph({required int revision, required RangeTicks range});
}
```

#### V2-D9 — الحفظ ذرّي دائماً

**القرار:** كتابة `<name>.part` ثم `fsync` ثم rename؛ لا كتابة في المكان.
**المرفوض:** الكتابة المباشرة — ملف تالف عند انقطاع الكهرباء (QG-9).

---

## 10. Native Media Engine

### 10.1 ملكية الوظائف

| الوظيفة | المالك | السبب |
| --- | --- | --- |
| Probe (streams/codec/fps/rotation) | FFmpeg | أدق وأسرع، بلا graph |
| Hashing/dedupe | stdlib + BLAKE3 | مستقل عن المحرك |
| Proxy / thumbnails / waveform | FFmpeg | مسارات مستقلة عن التركيب |
| Text rasterization | Media Core (HarfBuzz+FreeType) | تشكيل عربي متطابق بين المعاينة والتصدير |
| Timeline composition / transitions | MLT | سبب اختيار MLT |
| Mixing / resampling | MLT (libavfilter داخلياً) | تزامن A/V |
| Encoding / muxing | MLT consumer avformat | بلا ترميز مزدوج |
| Loudness measure | FFmpeg `ebur128` | تحليل فقط، لا تعديل |
| faststart | FFmpeg | خطوة رخيصة بعد الإنتاج |

**قاعدة الفصل:** MLT يملك الزمن والتركيب؛ FFmpeg يملك الملف والترميز. لا يُسمح لـ MLT بأن يكون مصدر حقيقة للـ probe، ولا لـ FFmpeg بتركيب مسارات.

### 10.2 C ABI للعامل

```c
int  shadow_engine_initialize(const char* profile_json, char** err);
int  shadow_engine_probe(const char* path, const char* opts_json, char** result_json);
int  shadow_engine_preview_open(const char* graph_json, const char* viewport_json, char** session_json);
int  shadow_engine_preview_seek(const char* session_id, int64_t tick);
int  shadow_engine_preview_frame(const char* session_id, int64_t tick, void** rgba, int* w, int* h);
int  shadow_engine_render(const char* graph_json, const char* preset_json, const char* out_uri, char** job_json);
int  shadow_engine_cancel(const char* job_id);
int  shadow_engine_shutdown(void);
```

قواعد: كل دالة تُعيد كود خطأ موحداً ورسالة JSON؛ الذاكرة المُعادة تُحرَّر بـ `shadow_engine_free`؛ لا مؤشر C++ يعبر إلى Dart؛ الإلغاء تعاوني ومفحوص بين الإطارات وفي حلقات FFmpeg الطويلة.

### 10.3 مسار المعاينة

`play`: MLT → fMP4 chunked لـ local socket **داخل العامل** ثم إلى Dart عبر pipe (لا منفذ TCP عام).
`scrub`: seek + تركيب إطار + نقل RGBA عبر shared memory (≤ 8 MB) → texture.
كل جلسة TTL 30 ثانية خاملة، وجلسة واحدة فقط.

### 10.4 التصدير

```
preparing → validating graph/preset/output → first 3 frames validated
rendering → progress من عدّ الإطارات
encoding → flush
finalizing → faststart + fsync + atomic rename
succeeded | failed
```

#### V2-D10 — التصدير لا يبدأ قبل صلاحية أول 3 إطارات

**القرار:** فشل التركيب المبكر يُبلَّغ قبل استهلاك دقائق ترميز.
**المرفوض:** البدء ثم الفشل عند الإطار 500 — يهدر وقتاً ويشوّه تقدّم المهمة.

---

## 11. Local Persistence

| المكوّن | المحتوى | ملاحظة |
| --- | --- | --- |
| SQLite | فهرسة المشاريع/الجلسات/المهام/الأدوات/الموافقات/المزودين + WAL | ليس مصدر الحقيقة للتحرير |
| ملف المشروع | `*.ssproj` (SQLite خاص بالمشروع: document + ops) | مصدر حقيقة الوثيقة، ذرّي، قابل للنقل |
| Cache & Proxies | مشتقات قابلة للحذف والإعادة | مفتاحها hash المصدر + الإعدادات |
| Keyring | مفاتيح المزودين | لا نسخ في SQLite/logs |
| Logs & Recovery | سجلات منظمة + checkpoints | append-only + hash chain للـ audit |

جداول SQLite الأساسية: `projects`, `sequences`, `tracks`, `clips`, `assets`, `effects`, `transitions`, `agent_sessions`, `agent_messages`, `agent_tasks`, `tool_executions`, `approvals`, `provider_configs`, `execution_logs`.

#### V2-D11 — ملف المشروع هو المصدر، وقاعدة البيانات فهرس

**القرار:** يمكن حذف SQLite وإعادة بنائه من ملفات المشاريع؛ لا بيانات تحرير حصرية فيه.
**المرفوض:** SQLite وحده — يخلط الفهرس بالوثيقة ويجعل النسخ الاحتياطي هشاً.

---

## 12. Environment Adapter

| الفئة | المعلومات | الاستخدام |
| --- | --- | --- |
| OS/Arch | Linux/Windows، x86_64/arm64 | اختيار الثنائيات |
| CPU/RAM | cores، ذاكرة متاحة | adaptive profile |
| GPU | وجود وتسريع encode/decode | CPU fallback |
| Media | codecs/containers | رفض مبكر أو proxy |
| Storage | مساحة حرة | منع render عند < 1.5× التقدير |
| Engine | إصدارات MLT/FFmpeg | توافق العامل |
| Display | دقة/معدل تحديث | معاينة |

البروفايلات الثلاثة: Performance / Balanced / Low Resource، تُختار تلقائياً وتُعرض للمستخدم للتجاوز. القيم في الوثيقة **أمثلة** وليست قياسات جهاز.

---

## 13. العقود الداخلية

| الحد | الشكل | مصدر الحقيقة |
| --- | --- | --- |
| Agent ↔ Provider | `AIRequest` / `AIStreamEvent` / `AIToolDefinition` (Dart) | `contracts/providers` |
| Agent ↔ Tool | `AgentTool` / `ToolContext` / `ToolResult` + JSON Schema مغلق | `contracts/tools` |
| Agent ↔ Editing | `EditingService` بعمليات ذرّية ذات revision | `contracts/editing` |
| Editing ↔ Media | `RenderGraph` (JSON) + `RenderPreset` + `MediaBridge` | `contracts/media` + **الملحق أ/هـ من v1** |
| Media ↔ Flutter | shared memory + texture handle (FFI) | `contracts/media` |
| كل الحدود | `ShadowError { code, category, retryable, correlationId, details }` | §14.3 |

**قاعدة:** لا يوجد DTO شبكي. `RenderGraph` يبقى JSON لأن العامل native ويجب أن يبقى قابلاً للتسجيل والاختبار (fixtures).

---

## 14. Threading / Caching / Errors / Observability

### 14.1 الكاش

| المشتق | المفتاح | الإبطال |
| --- | --- | --- |
| probe | `source_hash` | تغيّر الملف |
| proxy | `source_hash + target profile` | إعدادات/دقة |
| thumbnail/sprite | `source_hash + tick + size` | — |
| waveform | `source_hash + sample_rate` | — |
| text raster | `text + font_hash + size + colors + dpi` | أي تغيير |
| frame (scrub) | `graph_hash + tick + viewport + quality` | `revision` أو graph |

حد الكاش: 20 GiB أو 15% من القرص، أيهما أصغر؛ LRU مع عدم حذف مشتقات مفتوحة.

### 14.2 نموذج الأخطاء

كل خطأ يحمل `code` ثابتاً، `category` (agent/provider/tool/perm/edit/media/store), `retryable`, `correlation_id`, و`details` مسطّحة بلا أسرار. الأخطاء تمر من العامل كما هي بلا إعادة تفسير.

### 14.3 أكواد v2 الأساسية

| الكود | الفئة | Retryable | الدلالة |
| --- | --- | --- | --- |
| `AGENT_BUDGET_EXCEEDED` | agent | لا | تجاوز حد استدعاءات/زمن/توكن |
| `AGENT_LOOP_DETECTED` | agent | لا | تكرار نفس الأداة والمدخلات |
| `AGENT_TIMEOUT` | agent | لا | تجاوز الزمن الكلي |
| `AGENT_CANCELLED` | agent | لا | إلغاء مستخدم |
| `PROVIDER_AUTH` | provider | لا | 401/403 |
| `PROVIDER_RATE_LIMIT` | provider | نعم | 429/5xx |
| `PROVIDER_UNSUPPORTED` | provider | لا | قدرة غير مدعومة |
| `PROVIDER_BUDGET_EXCEEDED` | provider | لا | ميزانية تكلفة/توكن |
| `TOOL_INVALID_ARGS` | tool | لا | خرق مخطط الأداة |
| `TOOL_NOT_FOUND` | tool | لا | أداة غير مسجّلة |
| `TOOL_FAILED` | tool | حسب الأداة | فشل تنفيذ |
| `PERM_APPROVAL_REQUIRED` | perm | لا | عملية تحتاج موافقة |
| `PERM_APPROVAL_INVALID` | perm | لا | موافقة منتهية/معاد استخدامها |
| `PERM_APPROVAL_TIMEOUT` | perm | لا | انتهت مهلة الموافقة |
| `PERM_PATH_ESCAPE` | perm | لا | مسار/ symlink خارج workspace |
| `EDIT_REVISION_MISMATCH` | edit | نعم | `expected_revision` قديم |
| `EDIT_INVALID_OPERATION` | edit | لا | خرق ثابت من ثوابت الوثيقة |
| `MEDIA_ASSET_MISSING` | media | لا | أصل مفقود |
| `MEDIA_UNSUPPORTED` | media | لا | codec/container غير مدعوم |
| `MEDIA_ENGINE_CRASH` | media | نعم | وفاة العامل، يُعاد التشغيل |
| `MEDIA_WORKER_UNAVAILABLE` | media | نعم | تعذّر تشغيل العامل |
| `STORE_CORRUPT` | store | لا | فشل سلامة SQLite/المشروع |
| `STORE_DISK_FULL` | store | لا | مساحة غير كافية |

أكواد المحرك `RG_*` (V-01..V-22) تبقى كما هي من v1.

### 14.4 Observability

سجلات JSON منظمة بحقول `ts, level, module, task_id, tool, revision, correlation_id, duration_ms`؛ بلا مفاتيح ولا محتوى ملفات؛ ملف واحد متدرّج 20 MB × 5. مقاييس محلية: زمن أول رمز، عدد الاستدعاءات، نسبة نجاح الأدوات، زمن التصدير ونسبة realtime.

---

## 15. ميزانيات الأداء

| المقياس | الهدف | كيف يُقاس |
| --- | --- | --- |
| UI frame | ≤ 16.7 ms p95 | Flutter timings |
| Scrub frame | ≤ 120 ms p95 | probe آلي |
| بدء معاينة play | ≤ 400 ms | session trace |
| Render 1080p30 | ≥ 0.8× realtime على 4 cores | benchmark |
| فتح مشروع 200 clip | ≤ 4 s | CI cold start |
| RSS الواجهة | < 800 MB | قياس دوري |
| RSS العامل | < 1.5 GB | قياس دوري |
| أول رمز من المزود | ≤ 2 s p95 (شبكة محلّية جيدة) | قياس Gateway |

---

## 16. التتبّع: متطلبات MVP → الوحدات

| المتطلب | الوحدات |
| --- | --- |
| واجهة تفاعلية (شات/تايملاين/معاينة) | desktop/app + desktop/preview |
| فتح فيديو/صورة/صوت | media_core + native/media_worker + local_storage |
| Preview | media_core + native/media_worker + desktop/preview |
| مشروع محلي | editing_core + local_storage |
| 3 مسارات على الأقل | editing_core + timeline UI |
| قص/تقسيم/تحريك | editing_core + tool_system |
| نصوص وانتقالات | editing_core + text raster + native/media_worker |
| مزودان على الأقل + مفاتيح آمنة | provider_gateway + keyring |
| Tool calling + مهمة مستقلة | agent_runtime + tool_system + context_engine |
| موافقة قبل حذف/استبدال | permissions |
| إلغاء واستعادة | agent_runtime/recovery + native cancel |
| تصدير صالح | native/media_worker + media_core |
| استهلاك موارد مضبوط | environment + scheduler |
| لا شبكة مطلوبة للتحرير | كل الوحدات (QG-5) |

---

## 17. أسئلة مفتوحة

| # | السؤال | الخيارات | ما يمنع الحسم |
| --- | --- | --- | --- |
| OQ-1 | هل يُشحن MLT/FFmpeg مرفقاً أم نظامياً؟ | (أ) مرفق بإصدار مثبّت (ب) نظامي | حجم الحزمة مقابل اتساق الإصدارات |
| OQ-2 | GPU encode في v1؟ | (أ) CPU فقط (ب) عند التوفر | تعقيد CI وعدد الأجهزة |
| OQ-3 | هل تُدمج الترجمة (burn-in) أم sidecar؟ | (أ) burn-in (ب) SRT | نطاق MVP |
| OQ-4 | هل يملك الوكيل مهمتين متوازيتين؟ | (أ) واحدة (ب) طابور | تعقيد الحالة والموافقات |
| OQ-5 | سياسة الاحتفاظ بالمشتقات | (أ) LRU 20 GiB (ب) بلا حد | مساحة القرص |
| OQ-6 | توقيع الحزم على Windows | (أ) v1 بلا توقيع (ب) توقيع | تكلفة وشهادة |

---

## 18. المُخرَجات التالية

| # | المُخرَخ | يعتمد على | «منتهٍ» يعني |
| --- | --- | --- | --- |
| D1 | Repository & File Structure + CI matrix | §2.1 | بناء فارغ ينجح على Linux وWindows |
| D2 | Data Model & Migrations | §11 | `migrate up` من فراغ، فتح/حفظ ذهاباً وإياباً |
| D3 | Internal Contracts (Dart) + tool JSON Schemas | §13 + ملحق أ/هـ | توليد الأنواع + اختبار contract |
| D4 | Media Worker PoC | §10 | 3 مسارات + crossfade + نص عربي → MP4، وعزل crash مُثبت |
| D5 | Editing Core Skeleton | §9 | 5 أوامر + undo 100 خطوة + اختبارات وحدة |
| D6 | Provider Gateway + Adapterان | §5 | tool calling وstreaming مع مزودين، ومفاتيح في keyring |
| D7 | Tool Registry + أول 3 أدوات | §7 | `scan_media`, `create_project`, `trim_clip` تعمل من محادثة |
| D8 | Permission Engine + Approval UX | §8 | 0 عملية Dangerous بلا موافقة، اختبار path escape |
| D9 | Recovery + Agent Checkpoints | §4.4 | استئناف بعد قطع الكهرباء |
| D10 | Integration & Test Plan | الكل | CI أخضر يشمل بوابات QG |

**بوابة قبل D4:** D2 وD3 مكتملان، لأن العامل يستهلك `RenderGraph` المعرَّف في العقود؛ لا يُكتب graph مرتين.

---

## ملحق أ — عقد المحرك (موروث من v1.0، مع فارق النقل)

**الموروث كما هو:** `rendergraph.schema.json` (14 نوعاً كائناً + 4 قيَم أساسية، كائنات مغلقة)، `rendergraph.effects.json`، `rendergraph.manifest.json` (331 حقلاً)، المثال المتحقَّق منه، والملحق هـ (القرارات الدلالية D-RG-1..7 وقواعد V-01..V-22). هذه هي المصدر الوحيد لأي نوع في `RenderGraph`.

**ما يتغيّر في v2 (فارق النقل فقط):**

| v1.0 | v2.0 | السبب |
| --- | --- | --- |
| `ipc_error` / `problem_dto` | `ShadowError` (§14.3) | لا HTTP ولا IPC عام |
| `render_start_request` / `render_http_request` | `shadow_engine_render(graph, preset, out_uri)` | نفس المحتوى، نقل دالة C ABI |
| `preview_open_request` / `preview_http_*` | `shadow_engine_preview_open/seek/frame` | نفس `ViewportV1` والمدى |
| `hello`/`hello_ack` | استدعاء `shadow_engine_initialize` يعيد `{protocol_version, engine_version, capabilities}` | نفس التفاوض على قناة stdio |
| `envelope` + `message_id` | حقل `correlation_id` في كل استدعاء | لا حاجة لمغلف رسائل |
| مشروع/استيراد/AI DTOs | أنواع Dart داخلية (`ProjectDto`… تصبح domain) | لا حدود شبكية |
| `job_status` / `job_event` | `MediaJobEvent` على قناة أحداث العامل | نفس الحقول الزمنية |

**غير متغيّر:** `RenderGraph` و`RenderPreset` والمؤثرات والانتقالات ووحدات ticks/ppm/millibel وكل قواعد الرفض. أي تعديل على الحقول يحتاج إصدار مخطط جديد، لا تعديلاً صامتاً.

---

## ملحق ب — فهرس ADR

| # | القرار | الحالة |
| --- | --- | --- |
| ADR-001 | Desktop-first، بلا Backend | معتمد (v2) |
| ADR-002 | Agent Runtime في Dart داخل التطبيق | معتمد (v2) |
| ADR-003 | عامل وسائط منفصل + shared memory + FFI للعرض | معتمد (v2) |
| ADR-004 | MLT للتركيب وFFmpeg للترميز | معتمد (v2) لكن بوابة PoC في D4 |
| ADR-005 | SQLite فهرس + ملف مشروع مصدر الحقيقة | معتمد (v2) |
| ADR-006 | ثلاثة تصنيفات مخاطر + موافقة لكل عملية | معتمد (v2) |
| ADR-007 | RenderGraph مخطط حقلي مغلق | معتمد (v1، موروث) |
| ADR-008 | لا أداة shell في v1 | معتمد (v2) |

---

## ملحق ج — خريطة الانتقال v1.0 → v2.0

| من v1.0 | المصير في v2.0 |
| --- | --- |
| §1 الأنظمة الأربعة | يُستبدل بـ §2 الوحدات الإحدى عشرة |
| §2.1/§2.2 شجرة الوحدات وقاعدة التبعية | يُستبدل بـ §2.1/§2.2 |
| §2.3 عقود HTTP/IPC | يُستبدل بـ §13 (Dart + C ABI)؛ الرسائل الشبكية تتقاعد |
| §2.4 منع تسرب المحرك | يبقى مبدأً؛ يُنفَّذ بقاعدة التبعية + منع `mlt` في أي عقد |
| §3 نموذج البيانات/DDL | يُستبدل بـ §11 + D2 (DDL الجديد)؛ جداول الوكيل تُضاف |
| §4 مسار الوسائط | يُستبدل بـ §10 (نفس ملكية MLT/FFmpeg) |
| §5 العمليات وIPC | يُستبدل بـ §3 + §10.2 (stdio + C ABI) |
| §6 حدود AI | يُستبدل بـ §5 + §6 (مزودون، سياق، ميزانيات) |
| §7 التزامن/الكاش/الأخطاء | يُستبدل بـ §14 |
| §8 التتبّع | يُستبدل بـ §16 |
| §9 أسئلة مفتوحة | تُستبدل بـ §17 |
| §10 المُخرَجات | تُستبدل بـ §18 |
| ملحق أ (RenderGraph) | **يُورَث** مع فارق النقل في ملحق أ أعلاه |
| ملحق ب (قاموس) | يبقى مرجعاً اصطلاحياً |
| ملحق ج (ADR v1) | يُستبدل بملحق ب هنا |
| ملحق د (رسائل IPC/HTTP) | **يتقاعد**؛ ما يلزمه محتوى انتقل إلى §5/§7/§13/§14 |
| ملحق هـ (المخطط الحقلي) | **يُورَث** كاملاً + ملفاته المعيارية |
| D1..D7 | تُستبدل بـ D1..D10 هنا |

**ضمان:** لا يضيع قرار مُتحقَّق منه: `rendergraph.schema.json` وسجل المؤثرات والمدقّقات تبقى تعمل، وقواعد V-01..V-22 تبقى نافذة.

---

## ملحق د — أكواد رفض حدود الوكيل

| # | الكود | الشرط |
| --- | --- | --- |
| T-01 | `TOOL_SCHEMA_INVALID` | مخطط الأداة نفسه غير صالح عند التسجيل (فشل إقلاع، لا يُسجَّل) |
| T-02 | `TOOL_DUPLICATE_NAME` | اسم أداة مكرر في السجل |
| T-03 | `TOOL_RESULT_TOO_LARGE` | نتيجة > 256 KiB بعد التقليص المسموح |
| T-04 | `TOOL_NOT_IDEMPOTENT_RETRY` | إعادة محاولة أداة `idempotent=false` بلا موافقة جديدة |
| A-01 | `AGENT_NO_TOOLS` | مهمة تتطلب أداة والمزود لا يدعم tool calling |
| A-02 | `AGENT_INVALID_PLAN` | خطة تشير إلى أداة غير مسجّلة |
| A-03 | `AGENT_CHECKPOINT_MISSING` | استئناف بلا checkpoint صالح |
| P-01 | `PROVIDER_STREAM_BROKEN` | انقطاع stream قبل رسالة نهائية |
| P-02 | `PROVIDER_TOOL_CALL_MALFORMED` | استدعاء أداة لا يطابق أي مخطط معلن |

---

*نهاية الوثيقة — `SS-ARCH-002` v2.0*
