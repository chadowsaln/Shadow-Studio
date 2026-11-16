# Shadow Studio — Software Architecture Specification v1.0

| الحقل | القيمة |
| --- | --- |
| Document ID | `SS-ARCH-001` |
| Version | `1.0` |
| Status | **Superseded** بـ `SS-ARCH-002` v2.0 — يبقى مرجعاً معيارياً لعقد المحرك (الملحق أ + الملحق هـ) |
| Scope | MVP (المرحلة 4 → 7 من حالة المشروع) |
| Audience | مهندسو Flutter، مهندسو Python/Backend، مهندسو C++/Media، مهندسو AI Integration |
| Supersedes | — (أول إصدار) · **Superseded by** `SS-ARCH-002` v2.0 |

> **قاعدة هذه الوثيقة:** هي **specification** لا implementation. لا تحتوي كوداً مصدرياً عدا **schema DDL** و**interface signatures**، لأنها هي الحدود الملزِمة بين الأنظمة الأربعة. كل ما هو مكتوب هنا يُعتبر قراراً معمارياً، وأي خروج عنه يحتاج Decision Record جديداً.

**القرارات المثبَّتة (غير قابلة لإعادة الفتح في هذا الإصدار):** Flutter desktop للواجهة، Python + FastAPI للـ backend، SQLite للتخزين، MLT/MLT++ كمحرك تحرير، FFmpeg لمعالجة الوسائط، Cloud AI providers، Linux + Windows، مجاني بالكامل، و**non-destructive editing** كمبدأ أساسي.

---

## 0. اصطلاحات الوثيقة

| المصطلح | المعنى الدقيق داخل هذا المستند |
| --- | --- |
| **System** | أحد الأنظمة الأربعة: Presentation / Editing Core / Media Core / AI Integration |
| **Module** | حزمة قابلة للنشر تملك حدوداً واضحة (package أو crate أو process) |
| **Port** | واجهة مجرّدة يملكها المستهلك (Consumer-owned interface) |
| **Adapter** | تنفيذ تقني لـ Port (MLT، FFmpeg، OpenAI، …) |
| **Contract** | عقد على الحدود: API schema أو wire protocol أو DTO، ومصدره الحقيقة الوحيد |
| **Tick** | وحدة الزمن الداخلية = **1/1,000,000 ثانية** (microsecond)، عدد صحيح |
| **Ticks** | كل المواضع والمدد في قاعدة البيانات والـ DTOs مخزّنة كـ `INTEGER` بوحدة Tick |
| **Document** | الحالة الكاملة للمشروع في الذاكرة (immutable snapshot) |
| **Revision** | عدّاد أحادي التزايد يُزاد مع كل `EditTransaction` مُثبَّتة |
| **Derived** | أي ملف ناتج (proxy، thumbnail، waveform، text raster) وليس أصلاً |

**اصطلاح الزمن:** نستخدم `INTEGER` بوحدة الـ microsecond بدل rational timebase لأن:
1. MLT و FFmpeg كلاهما يقبلان `av_rescale_q` من وإلى ميكروثانية بدقة كافية لكل معدلات الإطارات التجارية (23.976، 25، 29.97، 30، 50، 59.94، 60).
2. يمنع أخطاء الفاصلة العائمة في عمليات الـ trim المتسلسلة.
3. `frame_rate_num/den` يُخزَّن على `sequences` و`tracks` لتحويل tick ↔ frame عند الحاجة (snapping، عرض الـ timecode).

قاعدة التحويل: `frame = floor(tick * fps_num / (1_000_000 * fps_den))`، والـ snapping يتم دائماً على حدود الإطارات في الـ Editing Core لا في الواجهة.

---

## 1. نظرة عامة وأهداف الجودة

### 1.1 السياق

Shadow Studio تطبيق سطح مكتب لتحرير الفيديو والصور والصوت، بأربعة أنظمة منفصلة تتعاون عبر عقود صريحة. الهدف المعماري الأول ليس «محرر فيديو يعمل»، بل **محرر فيديو يمكن استبدال محركه دون لمس الواجهة**، ويمكن تطويره بواسطة عدة فرق بالتوازي دون تعارض على نفس الملفات.

### 1.2 الأنظمة الأربعة في سطر واحد

| # | System | المسؤولية في سطر | Language / Runtime |
| --- | --- | --- | --- |
| 1 | **Presentation** | كل ما يراه المستخدم ويلمسه: timeline UI، preview surface، panels، dialogs | Dart / Flutter |
| 2 | **Editing Core** | الحقيقة الوحيدة للمشروع: document، commands، undo، revisions، persistence | Python 3.12 |
| 3 | **Media Core** | تحويل الوسائط إلى بكسل وصوت: probe، proxy، compose، render، encode | C++ (MLT++) + FFmpeg |
| 4 | **AI Integration** | ترجمة نوايا التحرير إلى مهام سحابية، وإرجاع **مقترحات** لا تعديلات مباشرة | Python (async) |

### 1.3 أهداف الجودة (Quality Goals)

مرتبة بالأولوية. كل هدف له سيناريو قابل للقياس وطريقة تحقّق، ولا يُقبل الهدف بلا رقم.

| الأولوية | الهدف | السيناريو | الهدف القابل للقياس | كيف نتحقق |
| --- | --- | --- | --- | --- |
| QG-1 | **Non-destructiveness** | المستخدم يقصّ 500 مقطع ثم يُصدّر | 0 بايت معدّل في أي ملف أصلي؛ كل الـ exports في مسار جديد | اختبار آلي: hash الملف الأصلي قبل/بعد يساوي نفسه |
| QG-2 | **Responsiveness** | سحب playhead على timeline فيه 300 clip | 60 fps في الواجهة، scrub frame ≤ 120 ms p95 | Flutter frame timings + probe آلي على preview endpoint |
| QG-3 | **Crash isolation** | MLT يُنهار أثناء render | التطبيق يبقى حياً، الواجهة تُظهر فشل المهمة، المشروع سليم | fault injection: kill -SEGV على media worker |
| QG-4 | **Determinism** | نفس المشروع + نفس preset يُصدَّر مرتين | نفس عدد الإطارات ونفس checksum للـ audio-video streams | مقارنة `ffprobe` + `framemd5` |
| QG-5 | **Portability** | نفس الميزات على Linux وWindows | لا كود خاص بمنصة داخل الأنظمة الأربعة؛ الفروق فقط في `platform/` | CI matrix على الاثنين |
| QG-6 | **Startup** | فتح التطبيق على مشروع 200 clip | نافذة قابلة للتفاعل ≤ 2.5 s، timeline جاهز ≤ 4 s | قياس cold start في CI |
| QG-7 | **Memory** | مشروع 4 ساعات، 6 مسارات | RSS للـ backend < 1.5 GB، للـ UI < 800 MB | قياس دوري + budget في CI |
| QG-8 | **Zero marginal cost** | تشغيل كل الميزات غير الـ AI | 0 دولار؛ الـ AI اختياري بمفتاح المستخدم | مراجعة تبعيات + عدم وجود حساب إجباري |
| QG-9 | **Recoverability** | انقطاع كهرباء أثناء render | بعد إعادة التشغيل: 0 عملية ضائعة صامتة، آخر revision سليمة | قطع العملية في منتصف المراحل |
| QG-10 | **Testability** | اختبار Editing Core كاملاً بلا GPU ولا وسائط | اختبارات وحدة < 5 s للمجموعة | pytest بلا FFmpeg عبر fakes |

### 1.4 خارج النطاق (Non-Goals v1.0)

Cloud rendering، collaborative editing، text-to-video، mobile، advanced color grading، 3D، وكل ما هو مذكور في «خارج نطاق MVP». كذلك خارج النطاق معماريّاً: تعدد المستخدمين، وقاعدة بيانات شبكية، وربط Flutter بأي native media API مباشرة.

---

## 2. فصل الأنظمة الأربعة

### 2.1 شجرة الوحدات (Module Map)

```
shadow-studio/
├── apps/desktop/                 # Presentation (Flutter)
├── services/core/                # Editing Core (Python/FastAPI)  ← process: shadow_core
├── services/media/               # Media Core (C++/MLT++ + FFmpeg) ← process: shadow_media_worker
├── services/ai/                  # AI Integration (Python)       ← in-process module of core
├── packages/contracts/           # source of truth: OpenAPI + JSON Schema + .proto/msgpack schemas
└── platform/                     # OS glue: paths, named pipes, process supervision, installers
```

الوحدات الداخلية لكل نظام، مع **ما يُسمح لها بالاستيراد** (العمود الأخير هو قاعدة التبعية القابلة للفحص آلياً):

| System | Module | المسؤولية | يُسمح لها بالاعتماد على |
| --- | --- | --- | --- |
| Presentation | `desktop/app` | shell، routing، theming، DI | `desktop/features/*`, `desktop/api_client` |
| Presentation | `desktop/features/timeline` | عرض/تفاعل timeline، drag/trim gestures | `desktop/api_client`, `desktop/domain_view` |
| Presentation | `desktop/features/preview` | عرض stream، transport controls | `desktop/api_client` |
| Presentation | `desktop/api_client` | عميل مُولَّد من `packages/contracts/openapi.json` + WS client | **العقود فقط** |
| Presentation | `desktop/domain_view` | view models مشتقة من DTOs (لا منطق تحرير) | `api_client` DTOs |
| Editing Core | `core/domain` | `ProjectDocument`, value objects، invariants | stdlib فقط |
| Editing Core | `core/commands` | `EditCommand` implementations + inverses | `core/domain` |
| Editing Core | `core/ports` | `MediaEnginePort`, `AiProviderPort`, `Clock`, `BlobStore` | `core/domain` |
| Editing Core | `core/application` | use cases: import، apply، undo، render orchestration | `core/domain`, `core/commands`, `core/ports` |
| Editing Core | `core/persistence` | SQLite repositories، migrations، snapshotting | `core/domain`, `core/ports` |
| Editing Core | `core/api` | FastAPI routers، DTO mapping، WS hub | `core/application`, `core/persistence` |
| Editing Core | `core/adapters/media_rpc` | تنفيذ `MediaEnginePort` فوق IPC | `core/ports`, `packages/contracts` |
| AI Integration | `ai/capabilities` | تعريف capabilities والمقترحات | `core/domain` (قراءة فقط) |
| AI Integration | `ai/ports` | `AiProviderPort` | `core/domain` |
| AI Integration | `ai/providers/*` | OpenAI/Anthropic/Replicate… adapters | `ai/ports` |
| AI Integration | `ai/jobs` | جدولة، retry، circuit breaker، cost guard | `ai/ports`, `core/ports` |
| Media Core | `media/rpc_server` | framed IPC server | `media/engine` |
| Media Core | `media/graph` | `RenderGraph` → MLT XML | own |
| Media Core | `media/mltshim` | MLT++ wrapper بـ C ABI مستقر | libmlt, libav* |
| Media Core | `media/ffmpeg` | probe/proxy/thumbnail/waveform/mux | libav* |
| Media Core | `media/services` | registry للـ filters/transitions/text raster | own |

### 2.2 قاعدة التبعية (The Dependency Rule)

**نص القاعدة:**

> التبعيات تتجه دائماً نحو **العقود والـ domain**، ولا تعود أبداً. Presentation لا يعرف MLT. Media Core لا يعرف المشروع. AI Integration لا يكتب في المشروع.

مصفوفة التبعيات المسموحة (`→` = «يعتمد على»):

| From \ To | Presentation | Editing Core | Media Core | AI Integration | Contracts |
| --- | --- | --- | --- | --- | --- |
| **Presentation** | — | ✗ (لا استيراد كود) | ✗ | ✗ | ✅ HTTP/WS DTOs فقط |
| **Editing Core** | ✗ | — | ✅ عبر `MediaEnginePort` | ✅ عبر `AiProviderPort` | ✅ |
| **Media Core** | ✗ | ✗ | — | ✗ | ✅ (wire types فقط) |
| **AI Integration** | ✗ | ✗ (يقرأ DTOs المقترحات) | ✗ | — | ✅ |

**نتائج ملزمة:**

1. **Flutter لا يرى MLT.** لا يوجد أي import لـ `libmlt`، ولا أي DTO يحتوي `mlt_service` أو `mlt_profile` أو مسارات MLT XML. الـ DTOs تصف **نيّة تحرير** بمدى بشري (`Track`, `Clip`, `Effect` بمعرّف منطقي)، والتحويل إلى MLT يحدث داخل Media Core حصراً.
2. **Media Core عديم الحالة (stateless).** يستقبل `RenderGraph` كاملاً ومُحلّاً (resolved) في كل طلب، ولا يحتفظ بمرجع لـ `ProjectDocument`. لذلك يمكن تشغيل عدة workers أو إعادة تشغيل أحدهم دون أي استعادة حالة.
3. **Editing Core لا يستورد MLT ولا FFmpeg.** أي حاجة لوسائط تمر عبر `MediaEnginePort`، وهذا يجعل اختبار Core بالكامل بلا وسائط حقيقية.
4. **AI لا يعدّل المشروع.** ينتج `AiProposal`، والـ Editing Core هو الوحيد الذي يحوّله إلى `EditTransaction`. هذا يمنع «تعديلات شبحية» لا تظهر في undo.

**الإنفاذ الآلي (لا نعتمد على الانضباط):**

| الفحص | الأداة | يفشل الـ CI إذا |
| --- | --- | --- |
| Python import boundaries | `import-linter` contracts في `services/core/pyproject.toml` | استيراد `media` أو `mlt` أو `sqlite3` داخل `core/domain` |
| Flutter boundaries | `custom_lint` rule: `presentation_must_not_import_native` | أي `dart:ffi` أو package وسائط داخل `features/*` |
| DTO drift | `openapi-diff` + codegen check | `packages/contracts/openapi.json` تغيّر بلا regeneration للعميل |
| MLT leakage | grep gate في CI | ظهور `mlt` أو `MLT` في `packages/contracts/**` |
| C++ layering | `media/CMakeLists.txt` target-level deps | ربط `mltshim` مباشرة بواجهة الـ RPC |

### 2.3 العقود الأربعة (Boundary Contracts)

#### Contract A — UI ↔ Editing Core (The Editing API)

- **النقل:** HTTP/1.1 على `127.0.0.1` مع منفذ عشوائي، وWebSocket للأحداث.
- **الشكل:** JSON، `snake_case`، timestamps كـ ISO-8601 UTC، الوقت كـ `*_ticks` صحيحة.
- **مصدر الحقيقة:** `packages/contracts/openapi.json` (مُولَّد من FastAPI) و`packages/contracts/asyncapi.json` (أحداث الـ WS).
- **العميل:** يُولَّد لـ Dart آلياً. **ممنوع** كتابة HTTP calls يدوياً داخل `features/*`.

الـ DTOs الأساسية:

| DTO | يُستخدم في | ملاحظة |
| --- | --- | --- |
| `ProjectDto` | فتح/حفظ | id, name, revision, frame_rate, resolution, settings |
| `TimelineDto` | تحميل timeline | sequences + tracks + clips + transitions + text + markers |
| `AssetDto` | import/library | kind, duration, streams, proxy_ready, missing |
| `EditCommandDto` | كل تعديل | `{op_type, target, payload}` — انظر §3.5 |
| `EditResultDto` | نتيجة تعديل | `{revision, applied[], events[]}` |
| `PreviewSessionDto` | preview | `{session_id, mode, stream_url, profile}` |
| `RenderJobDto` | export | state machine §4.6 |
| `AiJobDto` / `AiProposalDto` | AI | §6.3, §6.4 |
| `ProblemDto` | أخطاء | RFC 9457 `application/problem+json` §7.3 |

**نقاط النهاية (v1، كلها تحت `/api/v1`):**

| Method | Path | الوظيفة | Idempotency |
| --- | --- | --- | --- |
| GET | `/health` | جاهزية + إصدارات engine | — |
| POST | `/projects` | إنشاء مشروع | `Idempotency-Key` |
| POST | `/projects/open` | فتح مشروع من مسار | — |
| GET | `/project` | المشروع المفتوح حالياً | — |
| POST | `/project/save` | flush + snapshot | — |
| GET | `/timeline` | TimelineDto عند revision محددة | — |
| POST | `/timeline/commands` | تنفيذ batch ذرّي | `If-Match: revision` |
| POST | `/timeline/undo` / `/redo` | خطوة أو batch | `If-Match` |
| POST | `/assets/import` | مسارات ملفات → import jobs | `Idempotency-Key` |
| GET | `/assets/{id}` | تفاصيل + derived status | — |
| POST | `/assets/{id}/relink` | إصلاح مسار مفقود | — |
| POST | `/preview/sessions` | فتح جلسة (play/scrub) | — |
| POST | `/preview/sessions/{id}/seek` | tick مطلوب | — |
| GET | `/preview/sessions/{id}/stream` | fMP4 (HTTP chunked) | — |
| GET | `/preview/sessions/{id}/frame?tick=` | JPEG لإطار واحد | — |
| DELETE | `/preview/sessions/{id}` | إغلاق | idempotent |
| POST | `/render/jobs` | بدء تصدير | `Idempotency-Key` |
| GET | `/render/jobs/{id}` | حالة + progress | — |
| POST | `/render/jobs/{id}/cancel` | إلغاء | idempotent |
| POST | `/ai/jobs` | بدء مهمة AI | `Idempotency-Key` |
| POST | `/ai/proposals/{id}/accept` | تحويل مقترح إلى edit | `If-Match` |
| GET | `/settings` / PATCH | تفضيلات | — |
| WS | `/events` | event stream | — |

**Envelope لكل حدث WS:**

```json
{ "type": "timeline.changed", "seq": 10432, "revision": 218,
  "at": "2026-11-16T12:00:00Z", "correlation_id": "…", "payload": { } }
```

أنواع الأحداث الملزمة: `project.opened`, `timeline.changed`, `asset.imported`, `asset.derived_ready`, `preview.state`, `render.progress`, `render.state`, `ai.progress`, `ai.proposal_ready`, `engine.degraded`, `problem.raised`.

**أشكال أجسام الطلبات/الردود** لـ `POST /preview/sessions` و`POST /render/jobs` (وأي رسالة إلى المحرك) معرَّفة حقلاً بحقل في **§أ.10**؛ وأشكال بقية النقاط (المشروع، الاستيراد، حالة أي مهمة، AI) ورسالة الخطأ الموحّدة في **الملحق د (§د.1–§د.8)**. لا يوجد نوع مُخترع خارج الملحقين.

#### Contract B — Editing Core ↔ Media Core (`MediaEnginePort`)

هذا هو **العقد الذي يمنع تسرّب MLT**. التوقيعات ملزمة بالمعنى؛ أسماء الحقول في الـ wire types تأتي من `packages/contracts/media.proto` (MessagePack). والتعريف النوعي الكامل لكائن `RenderGraph` (كل حقل، نوعه، تعداده، حدوده، وإلزامه) في **الملحق هـ** وملفه المعياري `rendergraph.schema.json`؛ لا يُخترع نوع خارجها.

```python
# services/core/core/ports/media.py
class MediaEnginePort(Protocol):
    async def probe(self, path: Path, *, timeout_s: float) -> MediaProbe: ...
    async def ensure_derived(self, req: DerivedRequest) -> DerivedHandle: ...
    async def open_preview(self, graph: RenderGraph, view: PreviewViewport) -> PreviewHandle: ...
    async def seek(self, h: PreviewHandle, tick: int) -> None: ...
    async def render(self, req: RenderRequest) -> RenderHandle: ...
    async def cancel(self, h: JobHandle) -> None: ...
    async def capabilities(self) -> EngineCapabilities: ...   # filters, transitions, codecs
    async def health(self) -> EngineHealth: ...               # version, GPU, degraded flags
```

المعنى الإلزامي لكل عنصر:

| العنصر | الضمان |
| --- | --- |
| `probe` | لا يعدّل الملف أبداً؛ يفتحه read-only؛ يُعيد خطأً مصنّفاً عند ملف تالف |
| `ensure_derived` | idempotent بمفتاح `cache_key`؛ آمن للاستدعاء المتوازي؛ ذرّي (temp + rename) |
| `open_preview` | يفتح graph مستقل؛ لا يتأثر بجلسات أخرى؛ يستهلك ذاكرة محدودة |
| `seek` | يضمن وصول أول إطار تالٍ ≤ 150 ms p95 على proxy |
| `render` | يعيد handle فوراً؛ التنفيذ async؛ progress عبر قناة أحداث منفصلة |
| `cancel` | يوقف العملية خلال ≤ 500 ms، ويحذف الملفات الجزئية |
| `capabilities` | تُقرأ عند startup لبناء قوائم Effects في الواجهة — **الواجهة تسأل Core، وCore تسأل Media** |

`RenderGraph` هو **العقد الحقيقي** وليس MLT XML: شجرة إطارات مُحلّلة (resolved) بلا مراجع للمشروع، تحتوي: profile (fps/resolution/colorspace)، tracks بترتيبها، clips مع `source_uri` و`source_in`، effects بمعرّف منطقي + params مُقيَّمة عند الـ tick المطلوب، transitions، وطبقات text كـ rasters. **حقول هذا الكائن وأنواعها ووحداتها وقواعد رفضه معرَّفة حرفياً في الملحق أ (حقولاً وقواعد رفض)؛ و`project_revision` فيه معلومة تتبّع فقط، لا حالة يقرأها المحرك.**

#### Contract C — Editing Core ↔ AI Integration (`AiProviderPort`)

```python
class AiProviderPort(Protocol):
    name: str
    async def capabilities(self) -> set[AiCapability]: ...
    async def submit(self, req: AiRequest) -> AiRemoteHandle: ...
    async def poll(self, h: AiRemoteHandle) -> AiRemoteStatus: ...
    async def cancel(self, h: AiRemoteHandle) -> None: ...
    def estimate_cost(self, req: AiRequest) -> CostEstimate: ...
```

#### Contract D — Core ↔ Preview Transport (للواجهة)

الواجهة تستهلك **بثاً** لا محركاً:

```dart
// apps/desktop/lib/api_client/preview.dart
abstract interface class PreviewClient {
  Future<PreviewSessionDto> open({required String sequenceId, required PreviewMode mode});
  Future<void> seek(String sessionId, int tick);
  Future<void> setPlaying(String sessionId, bool playing);
  Stream<PreviewStatDto> stats(String sessionId);
  Future<void> close(String sessionId);
}
```

### 2.4 كيف تُمنع «الواجهة المرتبطة بالمحرك» عملياً

سيناريو الخطر: نافذة Preview في Flutter تحتاج عرض صورة. الحلول الثلاثة وتقييمها:

| البدء | الأسلوب | القرار |
| --- | --- | --- |
| A | Flutter يعرض إطارات من MLT عبر FFI/Texture مخصص | ❌ مرفوض: يثبّت Flutter على MLT، ويجعل انهيار MLT يُسقط التطبيق (يخالف QG-3) |
| B | Media Core يكتب ملفات preview ويعيد مساراتها للواجهة | ❌ جزئياً: بسيط لكن زمن الاستجابة > 1 s، يخالف QG-2 |
| C | **Preview Transport**: Media Core يخدم stream محلياً، Flutter يشغّله بمشغّل فيديو عام (libmpv) ويسأل عن إطارات scrub | ✅ معتمد |

القرار C يعني أن الواجهة تعرف «HTTP video stream» فقط — مفهوم عام موجود في أي مشغّل. لو استُبدل MLT بـ GStreamer أو محرك خاص، **لا يتغيّر سطر واحد في Dart**. نفس المنطق ينطبق على الصوت: يُدمَج في الـ fMP4.

**جدول منع التسرّب (Anti-Corruption Ledger):**

| مفهوم MLT | أين يُترجم | ما تراه الواجهة |
| --- | --- | --- |
| `mlt_profile` | `media/graph` | `{width, height, fps_num, fps_den, sample_rate}` |
| `mlt_service` (filter/transition) | `media/services` registry | `effect_key` منطقي مثل `shadow.blur` |
| `producer`/`tractor`/`playlist` | `media/graph` | `Track` و`Clip` في DTO |
| `consumer` (avformat) | `media/ffmpeg` | `RenderPreset` (codec/bitrate/container) |
| مسار MLT XML | لا يُسلَّم أبداً للواجهة | — |

### 2.5 تدفّق الطلب النموذجي (نظرة سريعة)

```
Flutter tap "Split"
  └─ POST /timeline/commands {op: clip.split, at_tick} + If-Match: 218
       └─ Editing Core: validate → apply to Document → inverse → persist txn (revision 219)
            ├─ WS event timeline.changed (revision 219)
            └─ invalidate preview cache for [t-2s, t+2s]
Flutter re-renders timeline from event, calls /preview/sessions/{id}/seek
  └─ Media Engine: resolve RenderGraph at revision 219 → MLT graph → scrub frame
```

---

## 3. نموذج البيانات (Project & Timeline)

### 3.1 المبادئ

1. **كل شيء قابل للتعديل هو صف في قاعدة البيانات + عملية في سجل التعديلات.** لا حالة تحرير تعيش فقط في الذاكرة.
2. **الأصول read-only.** يُخزَّن `source_uri` + `source_hash`؛ لا نكتب في الملف الأصلي، ولا نعيد ترميزه في مكانه. (QG-1)
3. **المدد والمواضع أعداد صحيحة** بوحدة Tick.
4. **`revision` هو عنوان الحالة.** كل قراءة أو كتابة تمرّ بـ revision؛ الـ `If-Match` يمنع Lost Updates بين UI وAI ومهام الاستيراد.
5. **المشتقّات ليست جزءاً من المشروع.** تُخزَّن في `derived_media` ومفتاحها `cache_key`؛ يمكن حذفها كلها وإعادة بنائها بلا فقدان بيانات.

### 3.2 مخطط العلاقات

```
projects 1─┬─* assets 1─* asset_streams
           ├─* sequences 1─* tracks 1─┬─* clips 1─* clip_effects
           │                          ├─* transitions
           │                          ├─* text_overlays
           │                          └─* markers (via sequence)
           ├─* edit_ops (append-only)
           ├─   undo_state (1:1)
           ├─* render_jobs
           ├─* ai_jobs 1─* ai_proposals
           └─* derived_media (asset_id nullable لصور AI)
job_events (سجل تشغيلي، غير مرتبط بـ FK لتسريع الكتابة)
app_settings (global)
```

### 3.3 SQLite Schema (DDL v1)

**متطلبات المحرك:** SQLite ≥ 3.37 (STRICT tables)، مع `PRAGMA journal_mode=WAL`, `foreign_keys=ON`, `synchronous=NORMAL`, `busy_timeout=5000`. ملف واحد لكل مشروع: `<project>.ssproj` (وهو SQLite)، مع `-wal`/`-shm` بجانبه. حجم متوقع لـ 4 ساعات تحرير ثقيل: 30–80 MB.

```sql
-- ============ 0. إعدادات الاتصال (تُطبَّق عند كل فتح) ============
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA synchronous = NORMAL;
PRAGMA user_version = 1;

-- ============ 1. المشروع ============
CREATE TABLE projects (
  id              TEXT PRIMARY KEY,              -- uuidv7
  name            TEXT NOT NULL,
  schema_version  INTEGER NOT NULL,              -- نسخة مخطط الوثيقة (migrations)
  revision        INTEGER NOT NULL DEFAULT 0,    -- يزداد مع كل EditTransaction
  frame_rate_num  INTEGER NOT NULL CHECK (frame_rate_num > 0),
  frame_rate_den  INTEGER NOT NULL CHECK (frame_rate_den > 0),
  width           INTEGER NOT NULL CHECK (width  > 0),
  height          INTEGER NOT NULL CHECK (height > 0),
  sample_rate     INTEGER NOT NULL CHECK (sample_rate IN (44100, 48000, 96000)),
  channels        INTEGER NOT NULL CHECK (channels BETWEEN 1 AND 8),
  color_space     TEXT    NOT NULL DEFAULT 'bt709',
  settings_json   TEXT    NOT NULL DEFAULT '{}', -- snapping, autosave, proxies…
  created_at      TEXT    NOT NULL,
  updated_at      TEXT    NOT NULL
) STRICT;

-- ============ 2. الأصول (read-only) ============
CREATE TABLE assets (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL CHECK (kind IN ('video','audio','image','ai_generated')),
  display_name  TEXT NOT NULL,
  source_uri    TEXT NOT NULL,                  -- مسار مطلق (file://) — لا يُعدَّل
  source_hash   TEXT NOT NULL,                  -- BLAKE3 للمحتوى
  size_bytes    INTEGER,
  duration_ticks INTEGER,
  probe_json    TEXT,                           -- raw ffprobe (للتشخيص فقط)
  missing_since TEXT,                           -- NULL = موجود
  imported_at   TEXT NOT NULL,
  UNIQUE (project_id, source_hash)               -- dedupe عند الاستيراد
) STRICT;
CREATE INDEX idx_assets_project ON assets(project_id);

CREATE TABLE asset_streams (
  id             TEXT PRIMARY KEY,
  asset_id       TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  stream_index   INTEGER NOT NULL,
  media_type     TEXT NOT NULL CHECK (media_type IN ('video','audio','subtitle','data')),
  codec          TEXT,
  width          INTEGER,
  height         INTEGER,
  frame_rate_num INTEGER,
  frame_rate_den INTEGER,
  sample_rate    INTEGER,
  channels       INTEGER,
  bit_depth      INTEGER,
  rotation       INTEGER NOT NULL DEFAULT 0 CHECK (rotation IN (0,90,180,270)),
  start_ticks    INTEGER NOT NULL DEFAULT 0,
  duration_ticks INTEGER,
  language       TEXT,
  UNIQUE (asset_id, stream_index)
) STRICT;

-- ============ 3. التسلسلات والمسارات ============
CREATE TABLE sequences (
  id              TEXT PRIMARY KEY,
  project_id      TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  frame_rate_num  INTEGER NOT NULL,
  frame_rate_den  INTEGER NOT NULL,
  width           INTEGER NOT NULL,
  height          INTEGER NOT NULL,
  sample_rate     INTEGER NOT NULL,
  channels        INTEGER NOT NULL,
  background      TEXT NOT NULL DEFAULT '#000000',
  position        INTEGER NOT NULL DEFAULT 0,
  created_at      TEXT NOT NULL
) STRICT;

CREATE TABLE tracks (
  id           TEXT PRIMARY KEY,
  sequence_id  TEXT NOT NULL REFERENCES sequences(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL CHECK (kind IN ('video','audio','overlay')),
  position     INTEGER NOT NULL,                -- 0 = الأسفل في الـ video stack
  name         TEXT NOT NULL,
  enabled      INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  locked       INTEGER NOT NULL DEFAULT 0 CHECK (locked IN (0,1)),
  muted        INTEGER NOT NULL DEFAULT 0 CHECK (muted IN (0,1)),
  solo         INTEGER NOT NULL DEFAULT 0 CHECK (solo IN (0,1)),
  hidden       INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0,1)),
  height_px    INTEGER NOT NULL DEFAULT 64,
  volume_db    REAL NOT NULL DEFAULT 0.0,
  pan          REAL NOT NULL DEFAULT 0.0 CHECK (pan BETWEEN -1.0 AND 1.0),
  blend_mode   TEXT NOT NULL DEFAULT 'normal'
  -- لا قيد على position: إعادة الترتيب swap داخل txn
) STRICT;
CREATE INDEX idx_tracks_sequence ON tracks(sequence_id, position);

-- ============ 4. المقاطع ============
CREATE TABLE clips (
  id                  TEXT PRIMARY KEY,
  track_id            TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  asset_id            TEXT REFERENCES assets(id) ON DELETE RESTRICT, -- NULL لـ color/adjustment
  kind                TEXT NOT NULL CHECK (kind IN ('video','audio','image','color','adjustment')),
  timeline_start_ticks INTEGER NOT NULL CHECK (timeline_start_ticks >= 0),
  duration_ticks      INTEGER NOT NULL CHECK (duration_ticks > 0),
  source_in_ticks     INTEGER NOT NULL DEFAULT 0 CHECK (source_in_ticks >= 0),
  speed_num           INTEGER NOT NULL DEFAULT 1 CHECK (speed_num > 0),
  speed_den           INTEGER NOT NULL DEFAULT 1 CHECK (speed_den > 0),
  opacity             REAL NOT NULL DEFAULT 1.0 CHECK (opacity BETWEEN 0.0 AND 1.0),
  volume_db           REAL NOT NULL DEFAULT 0.0,
  transform_json      TEXT NOT NULL DEFAULT '{}', -- x,y,scale,rotate,anchor,crop
  mix_json            TEXT NOT NULL DEFAULT '{}', -- fade in/out, crossfade hints
  label               TEXT,
  enabled             INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  created_at          TEXT NOT NULL
) STRICT;
CREATE INDEX idx_clips_track_time ON clips(track_id, timeline_start_ticks);

CREATE TABLE clip_effects (
  id              TEXT PRIMARY KEY,
  clip_id         TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
  effect_key      TEXT NOT NULL,                -- 'shadow.blur' | 'mlt.luma' | 'shadow.color_balance'
  position        INTEGER NOT NULL,             -- ترتيب التطبيق
  enabled         INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  params_json     TEXT NOT NULL DEFAULT '{}',   -- قيم ثابتة
  keyframes_json  TEXT NOT NULL DEFAULT '[]'    -- [{tick, param, value, easing}] — v1 بسيط
) STRICT;
CREATE INDEX idx_clip_effects_clip ON clip_effects(clip_id, position);

-- ============ 5. الانتقالات ============
CREATE TABLE transitions (
  id              TEXT PRIMARY KEY,
  track_id        TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  boundary_ticks  INTEGER NOT NULL CHECK (boundary_ticks >= 0), -- نقطة التقاء المقطعين
  duration_ticks  INTEGER NOT NULL CHECK (duration_ticks > 0),
  transition_key  TEXT NOT NULL,                -- 'shadow.crossfade' | 'mlt.wipe'
  params_json     TEXT NOT NULL DEFAULT '{}',
  enabled         INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1))
) STRICT;
CREATE INDEX idx_transitions_track ON transitions(track_id, boundary_ticks);

-- ============ 6. النصوص (overlays) ============
CREATE TABLE text_overlays (
  id                  TEXT PRIMARY KEY,
  track_id            TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  timeline_start_ticks INTEGER NOT NULL,
  duration_ticks      INTEGER NOT NULL CHECK (duration_ticks > 0),
  content             TEXT NOT NULL,
  style_json          TEXT NOT NULL DEFAULT '{}',  -- font, size, color, stroke, shadow, rtl
  layout_json         TEXT NOT NULL DEFAULT '{}',  -- align, box, safe margins
  animation_in_key    TEXT,
  animation_out_key   TEXT,
  params_json         TEXT NOT NULL DEFAULT '{}'
) STRICT;
CREATE INDEX idx_text_track_time ON text_overlays(track_id, timeline_start_ticks);

-- ============ 7. العلامات ============
CREATE TABLE markers (
  id          TEXT PRIMARY KEY,
  sequence_id TEXT NOT NULL REFERENCES sequences(id) ON DELETE CASCADE,
  at_ticks    INTEGER NOT NULL,
  label       TEXT NOT NULL DEFAULT '',
  color       TEXT NOT NULL DEFAULT '#FFC107'
) STRICT;

-- ============ 8. سجل التعديلات (Append-only) ============
CREATE TABLE edit_ops (
  seq          INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id   TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  batch_id     TEXT NOT NULL,                    -- uuidv7 — الوحدة الذرّية للـ undo
  op_type      TEXT NOT NULL,                    -- 'clip.split' ...
  target_type  TEXT NOT NULL,                    -- 'clip','track','sequence','effect'
  target_id    TEXT,
  payload_json TEXT NOT NULL,                    -- الوسائط (arguments)
  inverse_json TEXT NOT NULL,                    -- عملية معاكسة قابلة للتنفيذ
  origin       TEXT NOT NULL CHECK (origin IN ('ui','ai','import','system')),
  applied_at   TEXT NOT NULL
) STRICT;
CREATE INDEX idx_edit_ops_project_seq ON edit_ops(project_id, seq);

CREATE TABLE undo_state (
  project_id   TEXT PRIMARY KEY REFERENCES projects(id) ON DELETE CASCADE,
  applied_seq  INTEGER NOT NULL,   -- آخر seq مُطبَّق (يمثّل موضع المؤشر)
  baseline_seq INTEGER NOT NULL DEFAULT 0  -- تحت هذا الرقم لا undo (compaction)
) STRICT;

-- ============ 9. مهام العرض/التصدير ============
CREATE TABLE render_jobs (
  id               TEXT PRIMARY KEY,
  project_id       TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  sequence_id      TEXT NOT NULL REFERENCES sequences(id) ON DELETE CASCADE,
  project_revision INTEGER NOT NULL,             -- الحالة المُراد تصديرها (snapshot semantics)
  preset_json      TEXT NOT NULL,                -- codec/container/bitrate/resolution/range
  output_uri       TEXT NOT NULL,
  state            TEXT NOT NULL CHECK (state IN
    ('queued','preparing','rendering','encoding','finalizing','paused','succeeded','failed','cancelled','interrupted')),
  progress         REAL NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 1),
  frames_done      INTEGER NOT NULL DEFAULT 0,
  frames_total     INTEGER,
  engine_version   TEXT NOT NULL,
  error_json       TEXT,
  created_at       TEXT NOT NULL,
  started_at       TEXT,
  finished_at      TEXT
) STRICT;
CREATE INDEX idx_render_jobs_project ON render_jobs(project_id, created_at);

-- ============ 10. مهام AI والمقترحات ============
CREATE TABLE ai_jobs (
  id              TEXT PRIMARY KEY,
  project_id      TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  capability      TEXT NOT NULL,                 -- §6.1
  provider        TEXT NOT NULL,
  model           TEXT,
  idempotency_key TEXT NOT NULL,
  state           TEXT NOT NULL CHECK (state IN
    ('queued','submitted','running','succeeded','failed','cancelled','expired')),
  attempts        INTEGER NOT NULL DEFAULT 0,
  request_json    TEXT NOT NULL,
  result_json     TEXT,
  error_json      TEXT,
  cost_estimate_usd REAL,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  UNIQUE (idempotency_key)
) STRICT;

CREATE TABLE ai_proposals (
  id           TEXT PRIMARY KEY,
  ai_job_id    TEXT NOT NULL REFERENCES ai_jobs(id) ON DELETE CASCADE,
  project_id   TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL,                    -- 'cuts' | 'captions' | 'audio_clean' | 'smart_reframe'
  preview_json TEXT NOT NULL,                    -- ما يُعرض للمستخدم قبل القبول
  ops_json     TEXT NOT NULL,                    -- بذرة edit_ops بعد القبول
  base_revision INTEGER NOT NULL,                -- revision التي بُني عليها
  accepted_at  TEXT,
  UNIQUE (ai_job_id)
) STRICT;

-- ============ 11. الوسائط المشتقة (Cache index) ============
CREATE TABLE derived_media (
  id             TEXT PRIMARY KEY,
  project_id     TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  asset_id       TEXT REFERENCES assets(id) ON DELETE CASCADE, -- NULL لـ AI assets
  kind           TEXT NOT NULL CHECK (kind IN
    ('proxy','thumbnail','sprite','waveform','text_raster','ai_asset','audio_preview')),
  cache_key      TEXT NOT NULL UNIQUE,           -- §7.2
  path           TEXT NOT NULL,
  bytes          INTEGER NOT NULL DEFAULT 0,
  width          INTEGER, height INTEGER, duration_ticks INTEGER,
  engine_version TEXT NOT NULL,
  created_at     TEXT NOT NULL,
  last_used_at   TEXT NOT NULL,
  pinned         INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0,1))
) STRICT;
CREATE INDEX idx_derived_asset ON derived_media(asset_id, kind);

-- ============ 12. سجل تشغيلي (لا FK: يُكتب بكثافة) ============
CREATE TABLE job_events (
  seq       INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id    TEXT NOT NULL,
  job_kind  TEXT NOT NULL CHECK (job_kind IN ('render','ai','import','proxy')),
  at        TEXT NOT NULL,
  type      TEXT NOT NULL,
  payload_json TEXT NOT NULL
) STRICT;
CREATE INDEX idx_job_events_job ON job_events(job_id, seq);

-- ============ 13. تفضيلات عالمية (ليست داخل المشروع) ============
CREATE TABLE app_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;
```

**قيود لا يعبّر عنها DDL (تُفرض في Editing Core، وهذا قرار واعٍ):**

| القيد | السبب |
| --- | --- |
| عدم تداخل clips على نفس المسار | يحتاج استعلامات مدى؛ يُفحص في `domain/invariants` قبل الـ commit |
| تطابق `kind` المقطع مع `kind` المسار (video↔overlay, audio↔audio) | قرار منطقي متغيّر مع الميزات |
| `transition.boundary_ticks` يقع بين مقطعين متجاورين فعلياً | يعتمد على الحالة الكاملة |
| `source_in + duration*speed ≤ asset.duration` | يحتاج سرعة كسرية وحسابات تقريب |
| `edit_ops` append-only | يُفرض بصلاحيات: لا `UPDATE`/`DELETE` على الجدول في repositories |

**الترحيل (Migrations):** `PRAGMA user_version` هو رقم المخطط. كل ترحيل ملف SQL مرقّم + اختبار «up من نسخة n-1 على مشروع حقيقي». `projects.schema_version` منفصل لأن مخطط **الوثيقة** (معنى `params_json`) قد يتغيّر بلا تغيير جداول؛ يُرحَّل عند الفتح مع نسخة احتياطية تلقائية `<project>.ssproj.bak-<v>`.

### 3.4 التمثيل في الذاكرة (In-Memory Representation)

الوثيقة في الذاكرة **immutable**؛ كل تعديل ينتج وثيقة جديدة تشترك في الأجزاء غير المتغيّرة (structural sharing). هذا يجعل undo/redo و«قارن حالتين» وsnapshot لـ render مجاناً تقريباً.

```python
# services/core/core/domain/document.py  — توقيعات فقط
@dataclass(frozen=True, slots=True)
class ProjectDocument:
    project: ProjectMeta
    revision: int
    assets: Mapping[AssetId, Asset]
    sequences: Mapping[SequenceId, Sequence]
    tracks: Mapping[TrackId, Track]
    clips: Mapping[ClipId, Clip]
    effects: Mapping[EffectId, ClipEffect]
    transitions: Mapping[TransitionId, Transition]
    texts: Mapping[TextOverlayId, TextOverlay]
    markers: Mapping[MarkerId, Marker]

@dataclass(frozen=True, slots=True)
class Sequence:
    id: SequenceId
    name: str
    profile: Profile            # fps_num/den, w, h, sample_rate, channels
    track_order: tuple[TrackId, ...]

@dataclass(frozen=True, slots=True)
class Track:
    id: TrackId
    sequence_id: SequenceId
    kind: TrackKind             # video | audio | overlay
    position: int
    name: str
    state: TrackState           # enabled/locked/muted/solo/hidden + volume_db/pan/blend

@dataclass(frozen=True, slots=True)
class Clip:
    id: ClipId
    track_id: TrackId
    asset_id: AssetId | None
    kind: ClipKind
    start: int                  # ticks على الـ timeline
    duration: int               # ticks على الـ timeline
    source_in: int              # ticks داخل المصدر
    speed: Fraction             # num/den
    opacity: float
    volume_db: float
    transform: Transform
    mix: ClipMix
    enabled: bool
```

**التراكيب المساعدة في الذاكرة (مشتقة، لا تُخزَّن):**

| Structure | الغرض | التعقيد المتوقع |
| --- | --- | --- |
| `TrackIndex` (sorted list + interval check) | hit-testing عند tick، اكتشاف التداخل O(log n + k) | لكل مسار |
| `id → object` maps | وصول O(1) لكل كيان | للوثيقة |
| `SequenceDuration` cache | طول التسلسل، يُبطَل عند أي تغيير يمسّ المسار المعني | لكل تسلسل |
| `clips_at(track, tick)` | نقطة واحدة فقط — أفضل من interval tree كامل في v1 | لكل مسار |

**Invariants تُفحص قبل كل commit** (`domain/invariants.py`، تُعيد `list[Violation]`):

1. `clip.start >= 0` و`clip.duration > 0`.
2. لا تداخل بين مقطعين على نفس المسار (حدود نصف مفتوحة `[start, start+duration)`).
3. `clip.kind` متوافق مع `track.kind`.
4. `source_in + duration*speed ≤ asset.duration` (مع تسامح ≤ إطار واحد).
5. `transition.boundary_ticks` يساوي بداية مقطع ونهاية مقطعه السابق على نفس المسار.
6. `track.position` مجموعة متصلة `0..n-1` بلا فراغات ولا تكرار.
7. `effect.position` متصلة `0..k-1` لكل مقطع.
8. `text.duration > 0` و`animation_in + animation_out ≤ duration`.

كل انتهاك يُعيد `ValidationProblem(code, path, message)` ولا يُكتب أي شيء في SQLite (الذرّية: فحص كامل للـ batch قبل أول كتابة).

### 3.5 تسجيل التعديلات غير المُدمِّرة (Non-Destructive Edit Recording)

#### 3.5.1 نموذج العملية

كل تعديل هو `EditCommand` **خالص (pure)**: يأخذ وثيقة، يُعيد وثيقة جديدة + قائمة أحداث + عملية معاكسة. لا I/O، لا وقت، لا عشوائية داخل `apply`.

```python
# services/core/core/commands/base.py — توقيعات فقط
class EditCommand(Protocol):
    op_type: str
    def target(self, doc: ProjectDocument) -> CommandTarget: ...
    def validate(self, doc: ProjectDocument) -> list[Violation]: ...
    def apply(self, doc: ProjectDocument) -> CommandResult: ...

@dataclass(frozen=True)
class CommandResult:
    document: ProjectDocument
    inverse: EditCommand          # يكفي وحده للـ undo
    events: tuple[DomainEvent, ...]
```

الأوامر الملزمة في MVP (كل واحدة لها inverse صريح):

| `op_type` | المعنى | inverse |
| --- | --- | --- |
| `clip.insert` | إضافة مقطع (trimmed) من أصل | `clip.delete` |
| `clip.delete` | حذف (lift أو ripple) | `clip.insert` مع الحالة الكاملة |
| `clip.split` | قطع عند tick (Cut/Split) | `clip.join` |
| `clip.join` | دمج مقطعين متجاورين من نفس الأصل (Merge) | `clip.split` عند الحد نفسه |
| `clip.trim` | تعديل in/out (Trim) | `clip.trim` بالقيم السابقة |
| `clip.move` | نقل بين مواضع/مسارات | `clip.move` للخلف |
| `clip.set_speed` | تغيير السرعة | القيم السابقة |
| `clip.set_props` | opacity/volume/transform | القيم السابقة |
| `track.insert` / `track.delete` / `track.reorder` / `track.set_state` | إدارة المسارات | معاكس مباشر |
| `effect.add` / `effect.remove` / `effect.set_param` / `effect.reorder` | المؤثرات | معاكس |
| `transition.add` / `transition.remove` / `transition.set_param` | الانتقالات | معاكس |
| `text.insert` / `text.update` / `text.delete` | النصوص | معاكس |
| `marker.add` / `marker.delete` | علامات | معاكس |
| `sequence.create` / `sequence.rename` | تسلسلات | معاكس |

**قاعدة الـ inverse:** يجب أن يكون `apply(inverse)` قادراً على استعادة الوثيقة **بالبايت المنطقي** (نفس الحقول، نفس المعرفات) لا بإعادة إنشاء معرفات جديدة. لذلك تُخزَّن الكيانات المحذوفة في `inverse_json` كاملة.

#### 3.5.2 المعاملة (EditTransaction) وترتيب الحفظ

`POST /timeline/commands` يقبل **batch ذرّي** = `EditTransaction` واحدة = `batch_id` واحد = خطوة undo واحدة.

ترتيب التنفيذ الإلزامي:

```
1. تحقق من If-Match (revision)          → 409 لو مختلفة
2. تحقّق من صحة كل op (schema)          → 422
3. apply على نسخة مسودة من الوثيقة
4. تحقّق من invariants                 → 422 (لا شيء يُكتب)
5. ابدأ SQLite transaction (IMMEDIATE)
     INSERT edit_ops (seq, batch, op, inverse, origin) × N
     UPSERT كل الكيانات المتأثرة (clips/tracks/…)
     UPDATE projects.revision = revision + 1, updated_at
     UPDATE undo_state.applied_seq = آخر seq
   COMMIT
6. استبدل وثيقة الذاكرة بالمسودة (بعد نجاح الـ commit فقط)
7. أرسل أحداث WS + أبطل caches + أبلغ PreviewSession
```

نقطة مهمة: **الكتابة إلى القرص قبل تبديل الذاكرة**، لأن الفشل بعد الـ commit وقبل التبديل غير ممكن عملياً (تبديل مرجع)، والفشل قبله يعني «لم يحدث شيء» — وهذا ما يجعل QG-9 ممكناً.

#### 3.5.3 Undo / Redo

**القاعدة المعتمدة:** `edit_ops` سجل append-only للأوامر الأمامية ومعاكساتها، و`undo_state.applied_seq` هو **مؤشر** على هذا السجل. لا تُكتب عمليات جديدة عند الـ undo؛ الترجيع هو تحريك المؤشر.

| العملية | الأثر على SQLite | الأثر على الذاكرة |
| --- | --- | --- |
| `undo` | تنفيذ inverses آخر batch (بترتيب عكسي) في txn واحد: UPSERT للكيانات المتأثرة + `applied_seq` = أول `seq` في ذلك الـ batch − 1 | الوثيقة تُستبدل بالنتيجة |
| `redo` | إعادة تنفيذ ops الـ batch أمامياً (تلك التي `seq` فوق المؤشر) + `applied_seq` = آخر `seq` فيه | نفس الشيء |
| تعديل جديد بعد undo | `DELETE` من `edit_ops` حيث `seq > applied_seq` (فرع «المستقبل» يُسقط) ثم append عادي | تطبيق على الحالة الحالية |
| إغلاق المشروع | لا شيء إضافي: الحالة الحالية موجودة في جداول الكيانات | — |

**لماذا هذا متسق مع §3.5.2:** الـ undo **يكتب** صفوف الكيانات (لأنها الحالة الحقيقية) لكنه **لا يضيف** ops. لذلك `applied_seq` يبقى الوحيد الذي يصف «أين نحن في التاريخ»، ويعمل للاتجاهين لأن كل ops محفوظة بمعاكساتها.

**قيود إضافية:**

1. `undo` لا يعبر `baseline_seq` (تحت هذا الرقم لا تاريخ متاح) — واجهة تعرض الزر معطّلاً، لا خطأً.
2. `undo` أثناء مهمة render نشطة لا يؤثر عليها: المهمة تعمل على `project_revision` مجمّدة (§4.5).

**Snapshots (Checkpoints) — قرار v1:** لا جدول snapshots منفصل. جداول الكيانات **هي** اللقطة الدائمة للحالة المطبَّقة، و`edit_ops` فوق `applied_seq` هي الـ redo history. لذلك التحميل = SELECT للكيانات + إعادة تطبيق ops الـ redo. تكلفة التحميل لمشروع 200 clip: < 120 ms، مقبولة، وتُبسّط كثيراً. إن تجاوز التحميل 500 ms في القياس، يُضاف جدول `document_snapshots(seq, blob)` في v1.1.

**Compaction:** عند تجاوز ops المؤكّدة 50,000 صف أو 20 MB، تُحذف ops الأقدم من `baseline_seq` (تاريخ لم يعد قابلاً للوصول بـ undo) وتُرفع `baseline_seq`. تُسجَّل العملية في `job_events`.

#### 3.5.4 `origin` وأثر الـ AI

كل عملية تحمل `origin`:

| origin | يظهر في undo؟ | ملاحظة |
| --- | --- | --- |
| `ui` | نعم | تفاعل مباشر |
| `ai` | نعم | لكن مجمّعة كـ batch واحد يحمل `ai_job_id` في payload، ليتراجع عنها بضغطة واحدة |
| `import` | نعم | عمليات إنشاء assets/tracks الأولية |
| `system` | لا | مثل تطبيع المسارات بعد ترحيل المخطط |

### 3.6 اشتقاق RenderGraph من الوثيقة

التحويل من Document إلى RenderGraph مسؤولية `core/application/render/resolver.py`، وهو **الحلقة الوحيدة** التي تعرف كيف تُترجم «نية تحرير» إلى «طلب محرك»:

```python
class RenderResolver(Protocol):
    def resolve(self, doc: ProjectDocument, sequence_id: SequenceId,
                range: TickRange, profile: RenderProfile) -> RenderGraph: ...
    def resolve_frame(self, doc: ProjectDocument, sequence_id: SequenceId,
                      tick: int, profile: RenderProfile) -> RenderGraph: ...
```

ضمانات:

1. **حتمية:** نفس (revision, range, profile) → نفس RenderGraph بايت-ببايت، لذا يمكن استخدام `cache_key` كمعرّف preview.
2. **تقييم keyframes عند حدود الـ range:** يُقيَّم أثر parametrized effect عند أول وآخر tick لكل segment؛ المحرك يستقبل قيمتين (أو منحنى) ولا يعرف عن الوثيقة.
3. **Trim وspeed:** `source_in` و`duration` يحسبان إلى `source_range` بصيغة مقرّبة للـ tick الأقرب بدون تراكم خطأ.
4. **طبقات النص:** تتحوّل إلى مراجع rasters جاهزة (`text_raster` cache keys) — لا نص يُرسل للمحرك، لأن تشكيل العربية يجب أن يكون متطابقاً بين المعاينة والتصدير (§4.4).

**التعريف المعياري للحقول** هو §أ.3–§أ.9، والناتج يجب أن يطابق `shadow.rendergraph/1`. أي حقل جديد لا يُضاف إلى الـ resolver قبل أن يأخذ صفاً في جدول التطابق (§أ.11) وقاعدة رفض في §أ.12.

---

## 4. مسار الوسائط (Media Pipeline)

### 4.1 مصفوفة الملكية: MLT مقابل FFmpeg

| الوظيفة | المالك | السبب |
| --- | --- | --- |
| Probe (streams, codec, fps, rotation) | **FFmpeg** (`ffprobe`) | أدق وأسرع من MLT، ولا يحتاج بناء graph |
| Content hashing / dedupe | **FFmpeg/stdlib** (BLAKE3 على الملف) | مستقل عن المحرك |
| Proxy transcode | **FFmpeg** | ترميز سريع بـ HW accel، جودة قابلة للتحكم |
| Thumbnails / sprite sheets | **FFmpeg** | `select`+`scale` أسرع بكثير من تشغيل graph |
| Audio waveform peaks | **FFmpeg** + حساب RMS في Media Core | يحتاج فك ترميز صوتي فقط |
| Text rasterization | **Media Core** (HarfBuzz + FreeType) | تشكيل عربي/RTL متطابق بين معاينة وتصدير |
| Timeline composition (layers, blend, transitions) | **MLT** | هذا هو سبب اختيار MLT |
| Frame-accurate mixing / audio resampling | **MLT** (libavfilter داخلياً) | ضمان تزامن A/V |
| Encoding للتصدير | **MLT consumer avformat** (libavcodec) | يمنع مرحلة ترميز مزدوجة |
| Muxing / container | **libavformat عبر MLT** | نفس السبب |
| Loudness normalization (measure) | **FFmpeg** (`ebur128`) | تحليل، لا تعديل |
| Fix-up/finalize (faststart) | **FFmpeg** (`-movflags +faststart`) في `finalizing` | خطوة رخيصة بعد الإنتاج |

**قاعدة الفصل:** MLT يملك **الزمن والتركيب** (ماذا يُعرض في الإطار t)؛ FFmpeg يملك **الملف والترميز** (كيف يُقرأ/يُكتب). لا نسمح لـ MLT بأن يكون «مصدر الحقيقة» للـ probe، ولا لـ FFmpeg بتركيب مسارات.

### 4.2 Import → Probe

```
User → POST /assets/import {paths[]}
  → ImportJob (async, queue)
      for each path:
        1. canonicalize + stat           → missing/duplicate/unsupported
        2. BLAKE3 hash (streamed, off-loop)  → dedupe check (project_id, source_hash)
        3. MediaEngine.probe(path)       → MediaProbe (streams, duration, rotation)
        4. INSERT assets + asset_streams (single txn)
        5. enqueue derived jobs: thumbnail, sprite, waveform, (proxy if needed)
        6. WS: asset.imported, then asset.derived_ready (per artifact)
```

قواعد ملزمة:

| الحالة | السلوك |
| --- | --- |
| ملف غير مدعوم (codec/container) | `problem` بـ `MEDIA_UNSUPPORTED`، لا يدخل المكتبة |
| ملف موجود بنفس hash | لا تكرار؛ يُعاد استخدام الـ asset ويُسجَّل `deduplicated: true` |
| VFR (variable frame rate) | يُقبل، يُطبَّع إلى CFR في الـ proxy، ويُحذَّر `MEDIA_VFR_NORMALIZED` |
| Rotation metadata | يُثبَّت في `asset_streams.rotation` ويُطبَّق عند التركيب لا بإعادة ترميز |
| ملف على شبكة/بطيء | import يستمر؛ preview يستخدم proxy عند جاهزيته فقط |
| مسار مفقود لاحقاً | `missing_since` يُملأ، الواجهة تُظهر relink، render يفشل بـ `MEDIA_ASSET_MISSING` |

**Proxy policy:** proxy يُنشأ فقط إذا تحقّق أي من: الدقة > 1080p، أو codec غير قابل للفك في الوقت الحقيقي (ProRes/DNxHD/HEVC 10-bit)، أو bitrate > 100 Mbps. الـ proxy: H.264 8-bit، 960×540 (أو نصف الدقة)، 30 fps max، audio AAC 48 kHz stereo. الأصل يبقى مرجع التصدير دائماً.

### 4.3 Preview (الجلسات)

جلسة المعاينة = كائن حالة في Media Core يحمل: RenderGraph محسوباً، profile، موضع playhead، وضع (play/scrub)، وback-pressure.

| الوضع | المسار | الاستخدام | زمن الاستجابة المستهدف |
| --- | --- | --- | --- |
| **play** | MLT → `avformat` consumer إلى fMP4 chunked عبر HTTP محلي | تشغيل متصل | بدء ≤ 400 ms، انزلاق < 1 إطار/دقيقة |
| **scrub** | MLT frame seek → encode JPEG (quality 85) → endpoint `/frame` | سحب playhead، drag trim | ≤ 120 ms p95 (من cache إن أمكن) |
| **thumbnails** | sprite sheet من `derived_media` (FFmpeg) | المسارات عند التصغير | ≤ 16 ms (ذاكرة) / ≤ 50 ms (قرص) |

بروتوكول الجلسة: `open(mode)` → `seek(tick)` (يُلغي طلباً سابقاً غير مكتمل، ويُعيد أحدث طلب دائماً — last-write-wins)، `setPlaying(bool)`، `close`. أثناء السحب يُمنع فتح جلسات جديدة؛ تُعاد استخدام واحدة (منع تسرّب الجلسات: كل جلسة لها TTL 30 ثانية خاملة).

**أشكال الرسائل:** `preview_open` و`ViewportV1` والرد و`POST /preview/sessions` في §أ.10، وتحقّق الـ graph نفسه بقواعد §أ.12.

**Audio:** يُدمج في الـ fMP4 (AAC 48 kHz). عند scrub لا صوت. لا يوجد مسار صوتي منفصل في v1 (يبسّط المزامنة).

### 4.4 Text rendering (قرار مرتبط بالعربية)

MLT's `qtext`/`pango` قد يختلف تشكيله بين المنصتين ويختلف عن Flutter's text layout. لذلك:

1. Media Core يرسم النص إلى RGBA (PNG أو PAM sequence) باستخدام HarfBuzz + FreeType بنفس الخطوط المرفقة.
2. الرسم يُخزَّن في `derived_media(kind='text_raster')` بمفتاح يشمل: المحتوى، الـ hash للخط، الحجم، الألوان، الحدود، الدقة، pixel ratio.
3. المعاينة في Flutter تعرض **نفس** الـ raster (تأتي من `/preview` كطبقة أو كإطار مُركَّب) — الضمان: ما تراه = ما يُصدَّر.
4. Animations (fade/slide) تُنفَّذ في MLT على الـ raster كـ affine/opacity، لا بإعادة رسم.

### 4.5 Export (التصدير)

```
POST /render/jobs {sequence_id, preset, output_uri, range?}
  → validate: preset, output path writable, assets present, disk space ≥ 1.5× estimate
  → snapshot: resolve RenderGraph at project_revision (لا يتأثر بتعديلات لاحقة)
  → state=queued → media worker picks up
     preparing : build MLT XML, open consumer, validate first 3 frames
     rendering : MLT render loop, progress from frame count
     encoding  : flush encoder, write moov/atoms
     finalizing: ffmpeg -movflags +faststart (إن لزم) → fsync → atomic rename
  → succeeded + job_events + WS render.state
```

**Presets في MVP:** `mp4-h264-1080p` (افتراضي)، `mp4-h264-720p`، `mp4-h264-4k`، `webm-vp9`، `wav-pcm` (صوت فقط)، `mp3-320` (صوت فقط)، `gif` (محدود 15s). كل preset يُعرَّف كـ JSON schema في `packages/contracts/presets/` ويُترجم في `media/graph/preset_map`، وكلها تستخدم حقول `RenderPresetV1` المعرَّفة في §أ.10 حصراً (لا حقول إضافية).

**قاعدة عدم الكتابة فوق:** المسار النهائي لا يُستبدل إلا بموافقة صريحة من المستخدم (`overwrite: true`)؛ وإلا `409 OUTPUT_EXISTS`. الكتابة دائماً إلى `<name>.part` ثم rename ذرّي.

### 4.6 State Machine لمهمة التصدير

```
                    ┌──────────────┐
        create ───► │    queued    │
                    └──────┬───────┘
                           │ worker acquired
                    ┌──────▼───────┐   invalid graph/assets
                    │  preparing   ├──────────────► failed
                    └──────┬───────┘
                           │ first frame ok
                    ┌──────▼───────┐
              ┌────►│  rendering   │◄────┐
              │     └──────┬───────┘     │ pause/resume (v1: pause فقط بين المقاطع)
              │            │ eof         │
              │     ┌──────▼───────┐     │
              │     │   encoding   │     │
              │     └──────┬───────┘     │
              │            │ flushed     │
              │     ┌──────▼───────┐     │
              │     │ finalizing   ├─────┘
              │     └──────┬───────┘
              │            │ atomic rename
              │     ┌──────▼───────┐
              └─────┤  succeeded   │
                    └──────────────┘

  أي حالة نشطة ──cancel──► cancelled (تنظيف الملفات الجزئية)
  أي حالة نشطة ──crash───► interrupted ──requeue──► queued (بحد أقصى محاولتين)
```

| من | إلى | الشرط | الأثر |
| --- | --- | --- | --- |
| — | `queued` | طلب صالح | صف في `render_jobs`، `progress=0` |
| `queued` | `preparing` | worker متاح | resolve graph، فتح consumer |
| `preparing` | `rendering` | أول 3 إطارات بنجاح | بدء احتساب الإطارات |
| `preparing` | `failed` | graph غير صالح، asset مفقود، قرص ممتلئ | `error_json` مصنّف |
| `rendering` | `encoding` | آخر إطار | إغلاق الـ producer |
| `encoding` | `finalizing` | flush ناجح | faststart + fsync |
| `finalizing` | `succeeded` | rename ذرّي ناجح | `finished_at`، WS |
| أي نشطة | `cancelled` | طلب إلغاء | kill worker، حذف `.part` |
| أي نشطة | `interrupted` | worker crash / إغلاق التطبيق | لا يُحذف `.part` تلقائياً (تشخيص) |
| `interrupted` | `queued` | استئناف يدوي أو تلقائي (≤ محاولتان) | `attempts++` |
| `failed`/`succeeded`/`cancelled` | — | نهائية | لا انتقال |

**Invariants:**

1. `progress` غير تنازلي داخل نفس `render_job`.
2. `frames_done ≤ frames_total` عند وجود total.
3. `succeeded` يستلزم وجود ملف نهائي بحجم > 0 وقابل للقراءة بـ `ffprobe`.
4. `cancelled` يستلزم عدم وجود `.part`.
5. `project_revision` ثابت طوال عمر المهمة — التعديلات اللاحقة لا تؤثر (snapshot semantics).

**Progress وETA:** يعتمد على `frames_done / frames_total` عندما يكون total معروفاً (الأغلب)، وإلا على `tick / duration`. الـ ETA يُحسب بمتوسط متحرك لآخر 30 ثانية، ويُعرض «—» إن كان التباين عالياً. الإرسال عبر WS كل 250 ms max (coalesced) لتجنّب إغراق الواجهة.

---

## 5. الطوبولوجيا والعمليات (Process & IPC Topology)

### 5.1 العمليات (Processes)

| # | Process | Binary | العمر | المسؤولية | لماذا منفصل |
| --- | --- | --- | --- | --- | --- |
| P1 | **Desktop UI** | `shadow-studio` (Flutter) | عمر الجلسة | كل العرض والتفاعل + تشغيل stream المعاينة | منصة Flutter |
| P2 | **Core Host** | `shadow_core` (Python) | عمر المشروع | Editing Core + API + SQLite + AI orchestration | Python runtime، عزل عن UI |
| P3 | **Media Worker × N** | `shadow_media_worker` (C++) | طويلة (pool) | MLT graphs، FFmpeg، text raster | انهيار MLT لا يقتل التطبيق (QG-3) |
| P4 | **ffmpeg / ffprobe** | نظامي أو مرفق | قصير | probe، proxy، thumbnail، waveform، faststart | عزل + استخدام CLI المستقر |
| P5 | **AI** | داخل P2 | — | HTTP out، لا عملية منفصلة في v1 | لا يحتاج عزل ذاكرة |

عدد workers: `min(4, max(2, cpu_count // 2))`، وقابل للضبط. عامل واحد يُخصَّص لـ preview (dedicated) لضمان QG-2، والباقي للـ render/derived. عند الضغط، أولوية preview أعلى (schedule priority).

### 5.2 Startup وHandshake

```
1. Flutter يبدأ → ينشئ dir للجلسة (XDG_RUNTIME_DIR أو %LOCALAPPDATA%\Temp\ShadowStudio\<pid>)
2. Flutter يشغّل shadow_core --port 0 --token-file <runtime>/session.json --project <path?>
3. Core يكتب session.json (0600): {port, token(base64url 32B), pid, api_version}
4. Core يبدأ media workers (lazy: عند أول حاجة) ويكتب جاهزيتها في /health
5. Flutter يقرأ الملف، يحذفه، ويتصل بـ GET /health (يتحقق من api_version)
6. WS connect: /events?token=…  → يتلقى snapshot + seq الحالي
7. Flutter يعرض النافذة بعد الخطوة 5 (≤ 2.5 s من الإقلاع)
```

**قواعد الأمان (إلزامية):**

| القاعدة | التنفيذ |
| --- | --- |
| Loopback فقط | bind على `127.0.0.1` (IPv4) و`::1`؛ رفض أي interface آخر |
| Token إلزامي | `Authorization: Bearer` على كل طلب، ومقارنة constant-time |
| لا token في argv | يُمرَّر عبر ملف 0600 أو stdin، ويُحذف بعد القراءة |
| Origin check | WS يرفض أي `Origin` غير `null`/`file://` |
| لا وصول شبكي | Core لا يفتح منافذ غير loopback؛ AI فقط outbound HTTPS |
| حجم الجسم | حد أقصى 2 MB لأي JSON (missions تُرسل كمسارات لا محتوى) |

### 5.3 بروتوكول Core ↔ Media Worker

| البند | القرار |
| --- | --- |
| النقل | Unix domain socket (`<runtime>/media.sock`) على Linux؛ **named pipe** (`\\.\pipe\shadow-media-<pid>`) على Windows |
| التغليف | رسائل بإطار `uint32 length` + MessagePack (مخطط في `packages/contracts/media.proto` كمصدر حقيقة) |
| النمط | request/response بـ `correlation_id` + قناة أحداث غير متزامنة على نفس الاتصال (multiplexed) |
| الحجم | ≥ 1 MiB: تُنقل الملفات كمسارات، لا بأجسام رسائل |
| الحالة | stateless: كل طلب يحمل RenderGraph كاملاً |
| الإلغاء | `cancel{job_id}` + worker يوقف عند أقرب حد إطار |
| الإصدار | `hello{protocol_version}` عند الاتصال؛ رفض عدم التطابق |

**أشكال الرسائل:** `hello`/`hello_ack`، `probe`, `ensure_derived`, `job_status`, `job_cancel`, `health`, `event`، ورسالة `ipc_error` معرَّفة حقلاً بحقل في **§د.2**، وقواعد الإلغاء في **§د.1**. الأسماء التالية ملخص لاكتشاف المرسل فقط، لا بديل عن الملحق د:

نموذج الرسائل (أسماء فقط، التفاصيل في مخطط الـ contracts):

```
hello{protocol_version, engine_version, capabilities}
probe{path}                         → probe_result{streams[], duration}
ensure_derived{kind, cache_key, …}   → derived{path, bytes}
preview_open{graph, viewport}        → preview{handle, stream_url}
preview_cmd{handle, op, tick}        → ack
render_start{job_id, graph, preset, output} → ack
render_cancel{job_id}                → ack
event{job_id, type, progress, frame, error?}   (worker → core، غير متزامن)
health{}                             → {ok, gpu, degraded[]}
```

### 5.4 تدفّق المهام والأحداث

```
        ┌────────────── Flutter (P1) ──────────────┐
        │   UI state (Riverpod/Bloc)  ◄── WS events│
        └───────┬────────────────────────▲─────────┘
   HTTP cmd     │                        │ timeline.changed / render.progress
                ▼                        │
        ┌────────────── Core (P2) ───────┴──────────┐
        │  Application  →  Document (memory)       │
        │       │                │                 │
        │       ▼                ▼                 │
        │  SQLite txn      RenderResolver           │
        │       │                │                 │
        │       ▼                ▼                 │
        │  JobQueue ────► MediaRpcClient ──────────┼──► Media Workers (P3)
        │       │                                   │        │
        │       └─► AiJobManager ──► HTTPS ─────────┼──► Cloud AI
        └───────────────────────────────────────────┘        │
                                                             ▼
                                                     ffmpeg/ffprobe (P4)
```

**ترتيب الأولويات في JobQueue:** preview > import/probe > render (user-initiated) > derived (thumbnail/waveform/proxy) > AI fetch. الأسباب: الاستجابة البصرية أولاً، والـ AI يحتاج عادة تحميلاً خارجياً طويلاً.

**Backpressure:** طابور بطول أقصى (preview 2، render 8، derived 64). عند الامتلاء: `429 RESOURCE_EXHAUSTED` للـ API، ورسالة UI واضحة، وإلغاء الـ derived الأقل أهمية.

**التعافي من الفشل:**

| الفشل | الكشف | الاستجابة |
| --- | --- | --- |
| Media worker crash | EOF على المقبس + exit code | إعادة تشغيل worker، إعادة المهام النشطة إلى `interrupted` ثم requeue (≤2)، WS `engine.degraded` إن تكرر 3 مرات/دقيقة |
| Core crash | Flutter يفقد WS | نافذة «استعادة»: إعادة تشغيل Core، فتح نفس المشروع (WAL يُعيد الحالة)، عرض المهام المتوقفة |
| UI crash | Core يفقد WS | Core يستمر (لا يقتل نفسه)، ينظّف جلسات preview بعد 30s |
| SQLite مشغول | `SQLITE_BUSY` | `busy_timeout=5000` + retry واحد ثم `503 STORAGE_BUSY` |
| قرص ممتلئ | رفض الكتابة | إيقاف المهام، `507 DISK_FULL`، لا corruption (كنا نكتب `.part`) |

### 5.5 ملفات حالة على القرص

| المسار | المحتوى | العمر |
| --- | --- | --- |
| `<project>.ssproj` | SQLite (المشروع) | دائم |
| `<project>.ssproj-wal/-shm` | WAL | مع القاعدة |
| `<cache>/derived/<xx>/<hash>.<ext>` | proxies/thumbs/raster/waveforms | LRU |
| `<cache>/preview/<session>/` | fMP4 segment buffers | 30s بعد الإغلاق |
| `<runtime>/session.json` | port + token | يُحذف بعد القراءة |
| `<runtime>/media.sock` \| named pipe | IPC | عمر الجلسة |
| `<config>/settings.json` | تفضيلات (نسخة من `app_settings`) | دائم |
| `<logs>/core-YYYYMMDD.log` | logs مع correlation ids | 14 يوماً |

مسارات منصة: Linux `$XDG_DATA_HOME/shadow-studio`، `$XDG_CACHE_HOME/shadow-studio`، `$XDG_RUNTIME_DIR/shadow-studio`. Windows `%APPDATA%\ShadowStudio`، `%LOCALAPPDATA%\ShadowStudio\Cache`، `%LOCALAPPDATA%\Temp\ShadowStudio`.

---

## 6. حدود الذكاء الاصطناعي (AI Integration Boundary)

### 6.1 القدرات (Capabilities) في MVP

| Capability | المدخل | المخرج | الأثر على المشروع |
| --- | --- | --- | --- |
| `auto_cut` | transcript/energy analysis لمقطع صوتي | قائمة `cut` proposals مع timestamps | `clip.split` + `clip.delete` كـ batch |
| `captions` | مسار صوتي | segments نصية + timing | `text.insert` على مسار overlay |
| `audio_clean` | مقطع صوتي | ملف WAV معالَج (derived `ai_asset`) | استبدال مرجع الصوت داخل clip (بـ `clip.set_props`) |
| `smart_reframe` | فيديو + نِسب أهداف | keyframed crop/transform | `clip.set_props` مع keyframes |
| `scene_detect` | فيديو | timestamps للمشاهد | `marker.add` فقط (غير مُدمِّر تماماً) |
| `transcribe` | صوت | transcript (يُخدَم لـ captions/auto_cut) | لا تعديل مباشر |

**غير مدعوم في v1:** توليد فيديو، إزالة خلفية حقيقية، upscaling، ترجمة صوتية فورية (streaming).

### 6.2 التجريد (Provider Abstraction)

```python
# services/core/core/ports/ai.py
@dataclass(frozen=True)
class AiRequest:
    capability: AiCapability
    inputs: tuple[AiInput, ...]        # مسارات ملفات/نصوص — لا محتوى مشروع
    options: Mapping[str, JsonValue]
    idempotency_key: str

@dataclass(frozen=True)
class AiRemoteHandle:
    provider: str
    remote_id: str
    poll_after_s: float

class AiProviderPort(Protocol):
    name: str
    async def capabilities(self) -> set[AiCapability]: ...
    async def submit(self, req: AiRequest) -> AiRemoteHandle: ...
    async def poll(self, h: AiRemoteHandle) -> AiRemoteStatus: ...   # PENDING|RUNNING|SUCCEEDED|FAILED|EXPIRED
    async def cancel(self, h: AiRemoteHandle) -> None: ...
    def estimate_cost(self, req: AiRequest) -> CostEstimate: ...

class AiRouterPort(Protocol):
    """اختيار provider حسب capability + التكلفة + الصحة"""
    def select(self, cap: AiCapability, opts: Mapping[str, JsonValue]) -> AiProviderPort: ...
    def fallback_chain(self, cap: AiCapability) -> tuple[AiProviderPort, ...]: ...
```

**قواعد ملزمة:**

1. **إعدادات المستخدم فقط:** المفاتيح تُقرأ من keychain/`app_settings` المشفّرة (libsecret/DPAPI)؛ لا مفاتيح مضمّنة في التطبيق (QG-8: التطبيق مجاني، والـ AI اختياري بمفتاح المستخدم).
2. **لا يخرج مشروع كامل أبداً:** تُرسل فقط الوسائط المطلوبة للـ capability (مقطع صوتي، إطار، transcript) بعد موافقة صريحة عند أول استخدام per-provider.
3. **Redaction:** المسارات المحلية تُحذف من الـ metadata، ولا يُرسل `project.name`.
4. **Adapters هم الوحيدون الذين يعرفون HTTP الخاص بمزوّد:** لا ذكر لـ OpenAI/Anthropic خارج `ai/providers/*`.

### 6.3 النموذج غير المتزامن

**عقود AI على الـ wire:** `POST /ai/jobs` و`ai_job_dto` و`ai_proposal_dto` و`POST /ai/proposals/{id}/accept` ومسارات الفشل/الانتهاء معرَّفة في **§د.6** (والحالة الموحّدة في §د.5).

دورة حياة `ai_jobs.state`:

```
queued ──submit──► submitted ──poll(RUNNING)──► running ──► succeeded
   │                   │                          │            │
   │                   │                          └─► failed   └─► proposal_ready
   │                   └─ 4xx دائم ─────────────────────────► failed
   └─ cancel ──────────────────────────────────────────────► cancelled
                                                              expired (24h غير مُستلَم)
```

| القاعدة | القيمة |
| --- | --- |
| Polling | backoff أسّي `1s → 2 → 4 → 8 → 15 (سقف)` مع jitter ±20% |
| Timeout للمهمة | 10 دقائق قابلة للضبط per capability |
| حد التزامن | 2 مهام AI لكل مشروع، 4 عالمياً |
| Idempotency | `idempotency_key = blake3(capability, input_hashes, options)`؛ إعادة الطلب لا تكلّف مرتين |
| الاستمرارية | كل تغيّر حالة يُكتب في `ai_jobs` قبل إرسال الحدث (crash-safe) |
| مؤشر التقدم | coarse فقط (submitted/running/%) — لا progress دقيق من المزوّد |

### 6.4 من نتيجة إلى تعديل (Proposal Model)

هذه أهم قاعدة في هذا النظام: **الـ AI لا يلمس المشروع.**

```
result (provider JSON)
  → normalize → AiProposal {kind, preview, ops[], base_revision}
  → تخزين في ai_proposals (بدون أي تطبيق)
  → WS: ai.proposal_ready
  → UI يعرض preview (مثلاً: markers على timeline، أو captions في panel)
  → POST /ai/proposals/{id}/accept  ← قرار المستخدم
       ├─ If-Match: base_revision  (إن تغيّر → 409 STALE_PROPOSAL، تُعاد المعاينة)
       ├─ تحويل ops إلى EditCommand[] (origin='ai')
       └─ تنفيذها كـ batch واحد قابل للـ undo
```

**لماذا `base_revision`؟** لأن مقترح cuts محسوباً قبل 20 تعديلاً قد يقطع في المكان الخاطئ. الرفض الصامت أسوأ من الخطأ الظاهر.

### 6.5 الفشل والتراجع (Failure & Fallback)

| الحالة | السلوك | ما يراه المستخدم |
| --- | --- | --- |
| لا مفتاح API | التطبيق يعمل كاملاً بلا AI؛ الأزرار معطلة مع CTA «أضف مفتاحاً» | رسالة واحدة، لا إزعاج |
| مفتاح غير صالح (401) | `failed` نهائي، لا retry | «المفتاح مرفوض» + رابط للإعدادات |
| Rate limit (429) | retry مع `Retry-After`، ≤3 محاولات | «المزوّد مشغول، نعيد المحاولة…» + إلغاء |
| 5xx / timeout | failover إلى provider بديل في السلسلة، ثم `failed` | «تم التحويل إلى مزوّد بديل» |
| نتيجة غير صالحة (schema) | محاولة إصلاح واحدة (re-prompt بـ JSON mode)، ثم `failed` | «تعذّر فهم النتيجة» |
| انقطاع شبكة | `queued` مع انتظار، ≤3 محاولات، ثم `failed` | offline banner |
| نتيجة متأخرة بعد إلغاء | تُهمَل الحالة، لا تعديل | — |
| تجاوز سقف التكلفة | رفض قبل الإرسال | «يتجاوز الحد الشهري الذي حددته» |

**Circuit breaker:** لكل provider، 5 أخطاء 5xx خلال دقيقة → open لمدة 60s → half-open بمحاولة واحدة. الحالة تُعرَض في Settings → AI.

**Cost guard:** سقف شهري يضبطه المستخدم (افتراضي 0 = بلا سقف، مع تحذير). عند تجاوز 80% → إشعار. التقدير قبل الإرسال يُعرض في UI دائماً («~$0.04»).

**Degradation المحلي:** إن كان `transcribe` غير متاح، تُستخدم مقاييس طاقة الصوت (FFmpeg `astats`/`silencedetect`) لاقتراح cuts — أرخص وأسرع، ويُوسم المقترح `local_heuristic` بوضوح حتى لا يُظنّ أنه AI.

---

## 7. Threading / Caching / Error Model

### 7.1 نموذج التزامن

| المكوّن | النموذج | القاعدة |
| --- | --- | --- |
| FastAPI (P2) | event loop واحد (uvicorn) | لا عمل blocking > 5 ms على الـ loop |
| Hashing / probe orchestration | `ThreadPoolExecutor(4)` | لا استدعاء native ثقيل في الـ threads (الـ GIL + الاستقرار) |
| SQLite | **thread كاتب واحد** (dedicated) + connections قارئة | كل command يُنفَّذ في الكاتب؛ القراءات في threads منفصلة بـ WAL |
| Document access | single-writer lock (`asyncio.Lock`) per project | كل تعديل متسلسل؛ القراءات snapshot فورية |
| Media workers | عمليات منفصلة، تتوازى بحرية | لا shared memory مع Core |
| MLT render | threads داخلية في worker | نضبط `MLT_REPOSITORY` و`mlt_profile` فقط — لا نضيف threads من عندنا |
| AI | `asyncio` + `httpx.AsyncClient` مشترك | connection pool 20، timeout إلزامي |
| Flutter | isolate واحد للـ UI + isolates قصيرة للتحليل المحلي | كل I/O عبر HTTP لا في UI isolate |

**قاعدة الذهب:** أي عملية قد تتجاوز 5 ms ولا يمكن إلغاؤها، تُنفَّذ في **عملية أخرى** أو thread pool، لا على event loop. هذا يمنع تجميد الواجهة غير المباشر (VIA timeouts).

### 7.2 الكاش (Caching)

| الطبقة | المفتاح | الموقع | الإبطال / التخلص |
| --- | --- | --- | --- |
| Derived media (proxy/thumb/sprite/waveform/text) | `cache_key = blake3(kind, asset_hash, params_canonical_json, engine_version, profile)` | disk + index في `derived_media` | LRU بحجم (افتراضي 20 GB)، pinned للـ assets المستخدمة في مشروع مفتوح |
| Preview frames (scrub) | `blake3(revision, tick, preview_profile, graph_hash)` | memory LRU (≤ 300 إطار) + disk اختياري | إبطال عند `timeline.changed` في نطاق متأثر `[t-2s, t+2s]` |
| Rendered export | لا كاش (باهظ) | — | — |
| AI results | `idempotency_key` | `ai_jobs.result_json` | 30 يوماً |
| Probe results | `asset_hash` | `assets.probe_json` | دائم |
| Timeline DTO | `revision` | memory، per request | مع كل revision |
| Fonts / raster | `blake3(font_bytes, size, dpi)` | derived | LRU |

**قواعد:**

1. **Content-addressed دائماً** — لا كاش مبني على `(path, mtime)` لأنه ينكسر مع relink/copy.
2. **الـ canonical JSON** للـ params (ترتيب مفاتيح ثابت) قبل الـ hashing، وإلا انفجر عدد المدخلات.
3. **`engine_version` جزء من المفتاح** — ترقية MLT/FFmpeg تُبطل الكاش القديم بلا كود خاص.
4. **لا حذف أثناء الاستخدام:** `pinned` يمنع التخلص؛ التخلص يحدث في job خلفي بحد أقصى 200 ملف/دورة.
5. **إبطال Preview cache** دقيق بالنطاق، لا global invalidation (وإلا تم فقدان QG-2 عند التحرير الكثيف).

### 7.3 نموذج الأخطاء

**الشكل:** RFC 9457 `application/problem+json`:

```json
{ "type": "https://shadow.studio/problems/media-asset-missing",
  "title": "Asset missing", "status": 409,
  "code": "MEDIA_ASSET_MISSING",
  "detail": "…", "instance": "/api/v1/render/jobs/…",
  "correlation_id": "01J…", "retryable": false,
  "context": {"asset_id": "…", "path": "…"} }
```

**تصنيف الأكواد:**

| النطاق | البادئة | أمثلة | retryable | HTTP |
| --- | --- | --- | --- | --- |
| Validation | `VALIDATION_*` | `VALIDATION_OVERLAP`, `VALIDATION_SPEED_RANGE` | لا | 422 |
| Not found | `NOT_FOUND_*` | `NOT_FOUND_CLIP`, `NOT_FOUND_PROJECT` | لا | 404 |
| Conflict | `CONFLICT_*` | `CONFLICT_REVISION_MISMATCH`, `STALE_PROPOSAL` | نعم (أعد القراءة) | 409 |
| Media | `MEDIA_*` | `MEDIA_UNSUPPORTED`, `MEDIA_ASSET_MISSING`, `MEDIA_CORRUPT` | لا | 409/415 |
| Engine | `ENGINE_*` | `ENGINE_CRASH`, `ENGINE_UNSUPPORTED_FILTER`, `ENGINE_GPU_LOST` | نعم (مرة) | 503 |
| Storage | `STORAGE_*` | `STORAGE_BUSY`, `DISK_FULL`, `OUTPUT_EXISTS` | حسب | 503/507/409 |
| Resource | `RESOURCE_*` | `RESOURCE_EXHAUSTED`, `MEMORY_PRESSURE` | نعم (backoff) | 429 |
| AI | `AI_*` | `AI_NO_KEY`, `AI_INVALID_KEY`, `AI_QUOTA`, `AI_INVALID_RESULT` | حسب | 400/402/429/502 |
| Cancelled | `CANCELLED` | إلغاء مقصود | لا | 499 |
| Internal | `INTERNAL_*` | `INTERNAL_INVARIANT`, `INTERNAL_UNEXPECTED` | لا | 500 |

**قواعد:**

1. كل خطأ يحمل `correlation_id` موجوداً في logs — «اتصل بالدعم» بلا معرّف غير مقبول.
2. **لا stack traces للواجهة** أبداً؛ `detail` نص آمن + `context` منظم.
3. **i18n:** الواجهة تعرض من `code` لا من `detail`؛ `detail` للتشخيص/logs/تقارير.
4. **Engine failures لا تُخفى:** تُحوّل إلى `ENGINE_*` وتُسجَّل مع آخر 50 سطر stderr من worker.
5. **Retry policy واحدة** تُعرَّف central في Core؛ لا retry داخل adapters متعددة (يمنع retry storms).

### 7.4 Observability

| الإشارة | التنفيذ | القاعدة |
| --- | --- | --- |
| Logs | JSON lines، مستويات، `correlation_id`, `job_id`, `revision` | rotation 10 MB × 5 |
| Metrics | عدادات محلية (مدة render، مدة seek p95، معدل فشل) تُعرض في Diagnostics panel | لا إرسال تلقائي |
| Traces | span بسيط لكل طلب/مهمة (OpenTelemetry اختياري، معطّل افتراضياً) | opt-in |
| Crash reports | محلية فقط، مع زر «صدّر تقريراً» (يزيل المسارات الشخصية) | opt-in |

**المبدأ:** تطبيق مجاني بلا خادم = **لا telemetry افتراضية**. أي إرسال بيانات يحتاج موافقة صريحة (QG-8 والخصوصية).

### 7.5 ميزانيات الأداء (Performance Budgets)

| العملية | الميزانية | القياس |
| --- | --- | --- |
| `POST /timeline/commands` (batch 1) | ≤ 25 ms p95 | benchmark داخلي |
| تحميل مشروع 200 clip | ≤ 400 ms | اختبار CI |
| Scrub frame | ≤ 120 ms p95 | probe آلي |
| بدء playback | ≤ 400 ms | probe آلي |
| Import probe لملف 1 GB | ≤ 1.5 s (بلا hashing) | benchmark |
| Render 1080p30 (10 دقائق) | ≥ 0.8× realtime على 4 cores | benchmark يدوي |
| ذاكرة Core في وضع الخمول | ≤ 250 MB | قياس |

---

## 8. التتبّع (Traceability): متطلبات MVP → المكوّنات

| # | متطلب MVP | المكوّن المسؤول (Owner) | العقد / الواجهة | البيانات | الاختبار المقبول (Acceptance Test) |
| --- | --- | --- | --- | --- | --- |
| 1 | **Import** للفيديو/الصور/الصوت | `core/application/import` + `media/ffmpeg` probe | `POST /assets/import`, `MediaEnginePort.probe` | `assets`, `asset_streams`, `derived_media` | استيراد mp4/png/wav → 3 assets صحيحة + streams + thumbnail، مع dedupe عند التكرار |
| 2 | **Multi-track timeline** | `domain` (Sequence/Track/Clip) + `features/timeline` | `GET /timeline`, `TimelineDto`, `track.*`, `clip.move` | `sequences`, `tracks`, `clips` | 6 مسارات (3 video + 3 audio)، سحب مقطع بين مسارات، ترتيب ثابت بعد reload |
| 3 | **Cut / Trim / Split / Merge** | `core/commands/clip_*` | `POST /timeline/commands` (`clip.split`, `clip.trim`, `clip.join`, `clip.delete`) | `clips`, `edit_ops` | split عند playhead → مقطعان بلا فراغ؛ join يعيد الأصل؛ trim لا يتجاوز المصدر |
| 4 | **Video preview** | `media/preview` + `features/preview` | `POST /preview/sessions`, `GET /stream`, `/frame` | session state (لا DB) | تشغيل 30s بلا انزلاق، scrub 20 نقطة p95 ≤ 120 ms |
| 5 | **Text overlays** | `media/text` (raster) + `commands/text_*` | `text.insert/update`, `text_overlays` | `text_overlays`, `derived_media(text_raster)` | نص عربي RTL يظهر مطابقاً في المعاينة والتصدير (pixel diff < 2%) |
| 6 | **Transitions & Effects أساسية** | `media/services` registry + `commands/effect_*` | `effect.add`, `transition.add`, `EngineCapabilities` | `clip_effects`, `transitions` | crossfade + blur + brightness: مرئية في preview ومُصدَّرة بنفس الترتيب |
| 7 | **Audio editing** | `commands/clip_set_props` + MLT audio | `clip.set_props` (volume/pan), `track.set_state` (mute/solo) | `clips.volume_db`, `tracks.*` | 3 مقاطع صوتية، mute/solo، gain −6 dB → يقاس في التصدير |
| 8 | **Export بجودات مختلفة** | `render_jobs` + `media/render` | `POST /render/jobs`, state machine §4.6 | `render_jobs`, `job_events` | تصدير 1080p/720p/wav؛ الملف يعمل في مشغل خارجي؛ rev ثابت أثناء التعديل |
| 9 | **AI-assisted editing** | `ai/*` + `ai_proposals` | `POST /ai/jobs`, `/ai/proposals/{id}/accept` | `ai_jobs`, `ai_proposals`, `edit_ops(origin='ai')` | auto_cut على ملف 2 دقيقة → proposal → accept → batch واحد قابل لـ undo |
| 10 | **Project save/load** | `core/persistence` | `POST /project/save`, `POST /projects/open` | كل الجداول + `edit_ops` | إغلاق/فتح: نفس revision، نفس الترتيب، undo history محفوظ |

**تغطية القرارات الأربعة الكبرى في التتبّع:**

| القرار | أين يظهر في التصميم | كيف يُختبَر |
| --- | --- | --- |
| Non-destructive | §3.1، §3.5، §4.5 | hash الأصول قبل/بعد كامل رحلة المستخدم |
| فصل الأنظمة الأربعة | §2.1–§2.4 + بوابات CI | فحوص import-linter وcodegen drift |
| MLT غير مرئي للواجهة | Contract A + ledger §2.4 | grep gate + استبدال stub engine |
| AI لا يعدّل مباشرة | §6.4 | محاولة accept بـ revision قديمة → 409 |

---

## 9. Open Questions (تحتاج قراراً قبل/أثناء التنفيذ)

| # | السؤال | الخيارات | ما يتأثر | التوصية المؤقتة (default) |
| --- | --- | --- | --- | --- |
| OQ-1 | نطاق دعم GPU (NVENC/QSV/VideoToolbox) | (a) CPU فقط v1 (b) HW encode عند التوفر | زمن التصدير، حجم التنزيل، تعقيد CI | (a) CPU فقط، مع abstract `EncoderBackend` جاهز |
| OQ-2 | هل نوزّع MLT/FFmpeg مبنيّين أم نعتمد على النظام؟ | (a) مرفق (b) نظامي | حجم الحزمة، تناسق الإصدارات، QG-4 | (a) مرفق بإصدار مثبّت وم checksum |
| OQ-3 | فك ترميز HEVC 10-bit على أجهزة قديمة | (a) proxy إلزامي (b) رفض الاستيراد | تجربة المستخدم، زمن الاستيراد | (a) proxy إلزامي + تنبيه |
| OQ-4 | دعم VFR الأصلي في التصدير | (a) CFR دائماً (b) VFR passthrough | دقة التزامن، التعقيد | (a) CFR؛ VFR خارج النطاق |
| OQ-5 | حد حجم المشروع (مدة/عدد clips) | قرار رقمي | تصميم الفهرسة، snapshots | 4 ساعات / 2000 clip كسقف مُختبر |
| OQ-6 | الخطوط العربية الافتراضية وحقوقها | قائمة خطوط مرفقة | §4.4، الحزمة | خطان مفتوحان (Noto Naskh Arabic + Cairo) |
| OQ-7 | سلوك pause/resume للتصدير | (a) بين المقاطع فقط (b) كامل | تعقيد §4.6 | (a) في v1 |
| OQ-8 | هل يُسمح بتعدد المشاريع المفتوحة؟ | (a) مشروع واحد (b) نوافذ متعددة | topology، locks | (a) مشروع واحد لكل Core instance |
| OQ-9 | تخزين مفاتيح AI | (a) keychain (b) ملف مشفّر | الأمان، الاعتماديات | (a) libsecret/DPAPI عبر `platform/` |
| OQ-10 | هل الـ captions تُصدَّر كـ burn-in أم track؟ | (a) burn-in (b) sidecar SRT | نطاق §4.4 | (a) مع تصدير SRT اختياري |

---

## 10. Next Deliverables (بالترتيب)

| # | المُخرَج | يعتمد على | تعريف «منتهٍ» |
| --- | --- | --- | --- |
| D1 | **MVP UI/UX Design** (wireframes + interaction spec للـ timeline/preview) | هذه الوثيقة §2، §3 | شاشات كاملة لـ 10 متطلبات + حالات فراغ/خطأ/تحميل |
| D2 | **Repository & File Structure** (monorepo، CMake/pubspec/pyproject، CI matrix) | §2.1، §5 | شجرة ملفات مُنشأة + بناء فارغ ينجح على Linux وWindows |
| D3 | **API Contracts v1** (OpenAPI + AsyncAPI + media.proto + presets schema + generated clients) | §2.3، §5.3، الملاحق أ ود وهـ | الحقول كلها معرَّفة ومُتحقَّق منها آلياً؛ يبقى توليد OpenAPI/AsyncAPI/protobuf وcodegen والعميل واختبار contract |
| D4 | **Data Model & Migration Plan** (DDL v1 كملفات SQL + اختبارات ترحيل) | §3.3 | `migrate up` من فراغ ومن v0؛ فتح/حفظ ذهابا وإيابا |
| D5 | **Media Core Spike** (MLT graph → 3-track compose → fMP4 + mp4) | §4، §5.3 | تصدير 60s بـ crossfade + نص عربي بنجاح |
| D6 | **Editing Core Skeleton** (domain + 5 commands + undo + SQLite) | §3.4، §3.5 | اختبارات وحدة لأوامر cut/trim/split/join وundo 100 خطوة |
| D7 | **Integration & Testing Plan** (هرم الاختبار، fixtures وسائط، QG gates في CI) | كل ما سبق | خط CI أخضر يشمل بوابات §2.2 وميزانيات §7.5 |

**بوابة قبل D5:** يجب أن يكون D3 وD4 مكتملين، لأن Media Core يُستهلك عبر `RenderGraph` المعرَّف في الـ contracts — لا نكتب graph مرتين.

---

## ملحق أ — عقد RenderGraph وحدود المعاينة/التصدير (wire contract v1)

هذا الملحق **معياري (normative)**: حيث تختلف صياغة نثرية في §2–§5 مع ما هنا، يفوز هذا الملحق. وهو مُشتق آلياً ومُتحقَّق منه:

| الملف | الدور |
| --- | --- |
| [rendergraph.example.json](contracts/rendergraph.example.json) | مثال كامل لكل أشكال الرسائل (graph + preview + render) |
| [rendergraph.manifest.json](contracts/rendergraph.manifest.json) | قائمة الحقول: المسار + النوع + الوحدة + الإلزام |
| [validate_contract.py](contracts/validate_contract.py) | فحص آلي: الأنواع، الحقول غير المعلنة، القيود الدلالية، تطابق الجداول مع الـ DDL |

تشغيل الفحص: `python3 docs/architecture/contracts/validate_contract.py` (يفشل بخروج غير صفري عند أي انحراف).

### أ.1 الإطار (Envelope) والتفاوض على الإصدار

كل رسالة بين Core وMedia Worker تُرسَل كـ **MessagePack map** بإطار `uint32 BE length`. حقول الإطار:

| المسار | النوع | الوحدة | إلزامي | الدلالة |
| --- | --- | --- | --- | --- |
| `envelope_example.protocol_version` | int | — | نعم | إصدار البروتوكول؛ القيمة الحالية `1` |
| `envelope_example.message_id` | string (uuidv7) | — | نعم | معرّف فريد للرسالة، للـ dedupe وإعادة المحاولة |
| `envelope_example.correlation_id` | string (uuidv7) | — | نعم | يربط طلباً بردّه وبأحداثه وبتقرير السجل |
| `envelope_example.type` | string (enum) | — | نعم | `hello` \| `probe` \| `ensure_derived` \| `preview_open` \| `preview_cmd` \| `preview_close` \| `render_start` \| `render_cancel` \| `event` \| `health` \| `ack` \| `reject` |
| `envelope_example.sent_at_unix_ms` | int | ms | نعم | وقت الإرسال؛ يُستخدم للـ staleness فقط |
| `envelope_example.body` | object | — | نعم | جسم الرسالة حسب `type` |

**قاعدة التفاوض:** عند الاتصال تُرسل Core رسالة `hello` تحمل `protocol_version` و`min_supported` و`engine_version` و`capabilities`. يقبل الـ worker الاتصال فقط إذا كان `min_supported ≤ 1 ≤ protocol_version`؛ وإلا يردّ `reject{code:"PROTOCOL_MISMATCH"}` ويغلق القناة بلا أي رسالة أخرى.

**قواعد التوافق:**

1. داخل نفس الإصدار الرئيسي: يُسمح فقط بإضافة حقول **اختيارية**؛ القارئ **يتجاهل** الحقول غير المعروفة ولا يفشل بسببها.
2. إعادة تسمية حقل، حذفه، تغيير وحدته أو نوعه، أو تغيير معناه = إصدار رئيسي جديد (`protocol_version++`).
3. `graph_schema` مُصدَر مستقل عن `protocol_version` ويُفحص **في كل رسالة** تحمل graph؛ اختلافه = رفض.
4. لا يوجد "تفاوض ناعم": لا fallback إلى إصدار أقدم، ولا ترجمة على الحدود.

### أ.2 قاعدة الزمن (Time Representation) — قرار واحد صريح

> **كل الأزمنة أعداد صحيحة من الـ ticks بوحدة 1/1,000,000 ثانية، ومعدل الإطارات كسر منطقي `fps_num/fps_den`، ولا يوجد `float` للزمن في أي مكان على الـ wire.**

المبرر في سطر: الأعداد الصحيحة تجعل الـ graph قابلاً للتجزئة (hashing) بشكل حتمي وتُلغي تراكم خطأ التقريب عبر عمليات trim/split المتسلسلة، بينما يحفظ الكسر المنطقي دقة 30000/1001 دون ترميز عشري.

**النتائج الملزمة:**

| القاعدة | الصيغة |
| --- | --- |
| Tick ثابت عالمياً | `timebase.ticks_per_second = 1000000` دائماً؛ أي قيمة أخرى = رفض `RG_TIMEBASE_INVALID` |
| تحويل tick → frame | `frame = floor(tick * fps_num / (1000000 * fps_den))` |
| تحويل frame → tick | `tick = ceil(frame * 1000000 * fps_den / fps_num)` |
| خصائص الشفافية (opacity/alpha) | `ppm` صحيحة `0..1000000` (1e6 = 100%) |
| الكسب الصوتي | `millibel` صحيحة (mB): `0` = بلا تغيير، `-6000` = −6 dB |
| التماثل (pan) | `ppm` صحيحة `-1000000..1000000` (0 = مركز) |
| التحجيم (scale) | `ppm` صحيحة، `1000000` = 100% |
| الدوران | `rotation_quarter_turns` صحيحة `0..3` (ربع دورة) |

### أ.3 كائن RenderGraph — الجذر

الترتيب العام: `tracks` مرتّبة تصاعدياً بـ `position`؛ المسارات من النوع `video` و`overlay` تُركَّب من الأسفل للأعلى (position الأكبر = أعلى)، ومسارات `audio` تُخلط بترتيب `position` نفسه، ولا تدخل في التركيب البصري. `range` هو المدى الفرعي المطلوب فقط، ويُسمح بأن يكون داخل التسلسل الكامل.

| المسار | النوع | الوحدة | إلزامي | القيد / الدلالة |
| --- | --- | --- | --- | --- |
| `graph.graph_schema` | string | — | نعم | يساوي `shadow.rendergraph/1` حرفياً |
| `graph.sequence_id` | string (uuidv7) | — | نعم | للتشخيص والتتبّع فقط؛ الـ worker لا يقرأ قاعدة البيانات |
| `graph.project_revision` | int | revision | نعم | **مصدر تتبّع فقط**؛ يُسجَّل في السجلات ولا يؤثر على التنفيذ |
| `graph.timebase.ticks_per_second` | int | Hz | نعم | `1000000` حصراً |
| `graph.timebase.fps_num` | int | — | نعم | > 0، `fps = fps_num/fps_den ≤ 120` |
| `graph.timebase.fps_den` | int | — | نعم | > 0 (مثال 1001) |
| `graph.timebase.sample_rate` | int | Hz | نعم | `44100` \| `48000` \| `96000` |
| `graph.timebase.channels` | int | count | نعم | `1..8` |
| `graph.profile.width` | int | px | نعم | > 0؛ ويجب أن يكون زوجياً مع `yuv420p` |
| `graph.profile.height` | int | px | نعم | > 0؛ ويجب أن يكون زوجياً مع `yuv420p` |
| `graph.profile.pixel_format` | string (enum) | — | نعم | `yuv420p` \| `yuv422p` \| `yuv444p` \| `rgba` |
| `graph.profile.color_space` | string (enum) | — | نعم | `bt709` \| `bt2020` \| `srgb` |
| `graph.profile.interlaced` | bool | — | نعم | `false` في v1؛ `true` = رفض `RG_UNSUPPORTED_PROFILE` |
| `graph.range` | object (`RangeV1`) | — | نعم | مدى التركيب المطلوب |
| `graph.background_rgba` | string | `#RRGGBBAA` | نعم | لون الخلفية خلف أدنى مسار مرئي |
| `graph.tracks` | array of Track | — | نعم | قد تكون فارغة (تصدير شاشة سوداء)؛ الحد الأقصى 32 |

### أ.4 Track

| المسار | النوع | الوحدة | إلزامي | القيد / الدلالة |
| --- | --- | --- | --- | --- |
| `graph.tracks[].id` | string (uuidv7) | — | نعم | معرّف الكيان في الوثيقة (`tracks.id`)؛ شفاف للمحرك |
| `graph.tracks[].kind` | string (enum) | — | نعم | `video` \| `audio` \| `overlay` |
| `graph.tracks[].position` | int | index | نعم | فريد ومتواصل `0..n-1`؛ يحدد ترتيب التركيب/الخلط |
| `graph.tracks[].name` | string | — | نعم | للعرض في السجلات فقط؛ `""` مسموح |
| `graph.tracks[].enabled` | bool | — | نعم | `false` = لا يُساهم في الناتج (لكنه يبقى في الـ graph) |
| `graph.tracks[].gain_mb` | int \| null | mB | لا (لـ audio فقط) | نطاق `-60000..24000`؛ null لغير الصوت |
| `graph.tracks[].pan_ppm` | int \| null | ppm | لا (لـ audio فقط) | `-1000000..1000000` |
| `graph.tracks[].clips` | array of VideoClip \| null | — | لا (لـ video فقط) | مطلوب لـ `kind=video`، ومحظور لغيره |
| `graph.tracks[].audio_clips` | array of AudioClip \| null | — | لا (لـ audio فقط) | مطلوب لـ `kind=audio`، ومحظور لغيره |
| `graph.tracks[].text_layers` | array of TextLayer \| null | — | لا (لـ overlay فقط) | مطلوب لـ `kind=overlay`، ومحظور لغيره |
| `graph.tracks[].transitions` | array of Transition \| null | — | لا (لـ video/audio) | `null` مسموح؛ تُطبَّق على حدود المقاطع في نفس المسار |

### أ.5 VideoClip

| المسار | النوع | الوحدة | إلزامي | القيد / الدلالة |
| --- | --- | --- | --- | --- |
| `graph.tracks[].clips[].id` | string (uuidv7) | — | نعم | `clips.id` |
| `graph.tracks[].clips[].asset_id` | string \| null | — | نعم (قد يكون null) | null فقط عندما `kind ∈ {color}` |
| `graph.tracks[].clips[].kind` | string (enum) | — | نعم | `video` \| `image` \| `color` \| `adjustment` |
| `graph.tracks[].clips[].source_uri` | string (file://) \| null | — | شرطي | مطلوب لـ `video/image/adjustment`، وnull لـ `color` |
| `graph.tracks[].clips[].source_hash` | string (64 hex) \| null | — | شرطي | مطلوب مع `source_uri`؛ يُستخدم للتحقق من الهوية وللـ cache |
| `graph.tracks[].clips[].stream_index` | int | index | نعم | فهرس الـ stream داخل الأصل؛ `-1` = اختيار المحرك للأفضل |
| `graph.tracks[].clips[].timeline_start_ticks` | int | ticks | نعم | ≥ 0 وداخل `range` |
| `graph.tracks[].clips[].duration_ticks` | int | ticks | نعم | > 0؛ طول الظهور على الـ timeline |
| `graph.tracks[].clips[].source_in_ticks` | int | ticks | نعم | ≥ 0؛ نقطة البداية داخل المصدر |
| `graph.tracks[].clips[].speed_num` | int | — | نعم | > 0؛ السرعة = `speed_num/speed_den` |
| `graph.tracks[].clips[].speed_den` | int | — | نعم | > 0 |
| `graph.tracks[].clips[].opacity_ppm` | int | ppm | نعم | `0..1000000` |
| `graph.tracks[].clips[].enabled` | bool | — | نعم | `false` = لا يُركَّب |
| `graph.tracks[].clips[].label` | string \| null | — | لا | للعرض والتشخيص |
| `graph.tracks[].clips[].transform` | object (`TransformV1`) | — | نعم | التحويل الهندسي داخل إطار الـ profile |
| `graph.tracks[].clips[].effects` | array of Effect | — | نعم | `[]` مسموح؛ الحد 16 لكل مقطع |

### أ.6 Effect وParam وKeyframe (الأنواع المشتركة)

| المسار | النوع | الوحدة | إلزامي | القيد / الدلالة |
| --- | --- | --- | --- | --- |
| `graph.tracks[].clips[].effects[].id` | string (uuidv7) | — | نعم | `clip_effects.id` |
| `graph.tracks[].clips[].effects[].effect_key` | string | registry key | نعم | يجب أن يبدأ بـ `shadow.`؛ مفاتيح غير موجودة في `capabilities` = رفض |
| `graph.tracks[].clips[].effects[].enabled` | bool | — | نعم | `false` = يُهمَل |
| `graph.tracks[].clips[].effects[].params` | array of Param | — | نعم | `[]` مسموح؛ الحد 32 |
| `ParamV1.name` | string | registry key | نعم | من تعريف الـ effect؛ أي اسم غير معلَن = رفض |
| `ParamV1.type` | string (enum) | — | نعم | `int` \| `ppm` \| `color` \| `enum` \| `string` \| `bool` |
| `ParamV1.value` | variant | حسب النوع | نعم | يُطابق `type`؛ يُهمل منطقياً عند وجود keyframes |
| `ParamV1.keyframes` | array of Keyframe | — | نعم | `[]` = قيمة ثابتة؛ الحد 240 |
| `KeyframeV1.at_ticks` | int | ticks | نعم | **مطلق على الـ timeline**؛ تصاعدي تماماً، وداخل نطاق المقطع |
| `KeyframeV1.value` | variant | حسب نوع الـ param | نعم | قبل أول keyframe يُستخدم أولها، وبعد آخرها تُستخدم آخرها |
| `KeyframeV1.easing` | string (enum) | — | نعم | `linear` \| `ease_in` \| `ease_out` \| `ease_in_out` \| `step` |

**TransformV1** (يُستخدم في `clips[].transform` و`text_layers[].transform`):

| المسار | النوع | الوحدة | القيد |
| --- | --- | --- | --- |
| `TransformV1.x_px` | int | px | إزاحة أفقية؛ 0 = متمركز حسب `anchor` |
| `TransformV1.y_px` | int | px | إزاحة رأسية |
| `TransformV1.scale_x_ppm` | int | ppm | > 0؛ 1000000 = 100% |
| `TransformV1.scale_y_ppm` | int | ppm | > 0؛ 1000000 = 100% |
| `TransformV1.rotation_quarter_turns` | int | count | `0..3` |
| `TransformV1.anchor` | string (enum) | — | `top_left` \| `center` |
| `TransformV1.crop_left_px` | int | px | ≥ 0 ومجموعها < أبعاد المصدر |
| `TransformV1.crop_right_px` | int | px | ≥ 0 |
| `TransformV1.crop_top_px` | int | px | ≥ 0 |
| `TransformV1.crop_bottom_px` | int | px | ≥ 0 |

**RangeV1** (في `graph.range` و`render_http_request.range`):

| المسار | النوع | الوحدة | القيد |
| --- | --- | --- | --- |
| `RangeV1.start_ticks` | int | ticks | ≥ 0 |
| `RangeV1.duration_ticks` | int | ticks | > 0؛ `start + duration` ≤ طول التسلسل |

### أ.7 Transition

| المسار | النوع | الوحدة | إلزامي | القيد / الدلالة |
| --- | --- | --- | --- | --- |
| `graph.tracks[].transitions[].id` | string (uuidv7) | — | نعم | `transitions.id` |
| `graph.tracks[].transitions[].kind` | string (enum) | — | نعم | `crossfade` \| `dissolve` \| `wipe_left` \| `wipe_right` \| `fade_black` |
| `graph.tracks[].transitions[].at_ticks` | int | ticks | نعم | = `from_clip.timeline_start_ticks + from_clip.duration_ticks` بالضبط |
| `graph.tracks[].transitions[].duration_ticks` | int | ticks | نعم | > 0؛ ≤ نصف أقصر مقطع من الطرفين |
| `graph.tracks[].transitions[].from_clip_id` | string (uuidv7) | — | نعم | مقطع موجود على نفس المسار وينتهي عند `at_ticks` |
| `graph.tracks[].transitions[].to_clip_id` | string (uuidv7) | — | نعم | المقطع التالي مباشرة، يبدأ عند `at_ticks` |

### أ.8 TextLayer (بلا نص — rasters فقط)

| المسار | النوع | الوحدة | إلزامي | القيد / الدلالة |
| --- | --- | --- | --- | --- |
| `graph.tracks[].text_layers[].id` | string (uuidv7) | — | نعم | `text_overlays.id` |
| `graph.tracks[].text_layers[].raster_uri` | string (file://) | — | نعم | مسار raster جاهز (RGBA/PNG)؛ المحرك لا يرسم نصاً |
| `graph.tracks[].text_layers[].raster_hash` | string (64 hex) | — | نعم | blake3؛ يُتحقق منه قبل الاستخدام |
| `graph.tracks[].text_layers[].raster_width` | int | px | نعم | > 0؛ أبعاد الـ raster الأصلية |
| `graph.tracks[].text_layers[].raster_height` | int | px | نعم | > 0 |
| `graph.tracks[].text_layers[].start_ticks` | int | ticks | نعم | ≥ 0 وداخل `range` |
| `graph.tracks[].text_layers[].duration_ticks` | int | ticks | نعم | > 0 |
| `graph.tracks[].text_layers[].opacity_ppm` | int | ppm | نعم | `0..1000000`؛ يُضرب في alpha الـ raster |
| `graph.tracks[].text_layers[].transform` | object (`TransformV1`) | — | نعم | يوضع الـ raster داخل إطار الـ profile |
| `graph.tracks[].text_layers[].animation_in.kind` | string (enum) | — | نعم | `none` \| `fade` \| `slide` |
| `graph.tracks[].text_layers[].animation_in.duration_ticks` | int | ticks | نعم | `0` عندما `kind=none` |
| `graph.tracks[].text_layers[].animation_out.kind` | string (enum) | — | نعم | كما في `in` |
| `graph.tracks[].text_layers[].animation_out.duration_ticks` | int | ticks | نعم | `animation_in + animation_out ≤ duration_ticks` |

### أ.9 AudioClip

| المسار | النوع | الوحدة | إلزامي | القيد / الدلالة |
| --- | --- | --- | --- | --- |
| `graph.tracks[].audio_clips[].id` | string (uuidv7) | — | نعم | `clips.id` |
| `graph.tracks[].audio_clips[].asset_id` | string \| null | — | نعم (قد يكون null) | null = صمت مُدخل (silence) |
| `graph.tracks[].audio_clips[].source_uri` | string (file://) \| null | — | شرطي | مطلوب مع `asset_id` |
| `graph.tracks[].audio_clips[].source_hash` | string (64 hex) \| null | — | شرطي | مطلوب مع `source_uri` |
| `graph.tracks[].audio_clips[].stream_index` | int | index | نعم | `-1` = أفضل stream صوتي |
| `graph.tracks[].audio_clips[].timeline_start_ticks` | int | ticks | نعم | ≥ 0 وداخل `range` |
| `graph.tracks[].audio_clips[].duration_ticks` | int | ticks | نعم | > 0 |
| `graph.tracks[].audio_clips[].source_in_ticks` | int | ticks | نعم | ≥ 0 |
| `graph.tracks[].audio_clips[].speed_num` | int | — | نعم | > 0 (تغيير السرعة يُعيد أخذ العينات تلقائياً) |
| `graph.tracks[].audio_clips[].speed_den` | int | — | نعم | > 0 |
| `graph.tracks[].audio_clips[].gain_mb` | int | mB | نعم | `-60000..24000` |
| `graph.tracks[].audio_clips[].fade_in_ticks` | int | ticks | نعم | ≥ 0؛ `fade_in + fade_out ≤ duration` |
| `graph.tracks[].audio_clips[].fade_out_ticks` | int | ticks | نعم | ≥ 0 |
| `graph.tracks[].audio_clips[].enabled` | bool | — | نعم | `false` = يُهمَل |

> **مؤثرات الصوت:** غير موجودة في عقد v1. تعديل الصوت في MVP = gain/pan/fades فقط. أي `effects` على مسار صوتي = رفض `RG_UNKNOWN_FIELD`.

### أ.10 حدود المعاينة والتصدير (signatures بنفس الدرجة)

**رسالة `preview_open` (Core → Worker):**

| المسار | النوع | الوحدة | القيد |
| --- | --- | --- | --- |
| `preview_open_request.session_id` | string (uuidv7) | — | يولّده Core؛ فريد خلال عمر العملية |
| `preview_open_request.mode` | string (enum) | — | `play` \| `scrub` |
| `preview_open_request.start_tick` | int | ticks | داخل `graph.range` |
| `preview_open_request.viewport` | object (`ViewportV1`) | — | دقة المعاينة المطلوبة |
| `preview_open_request.graph` | RenderGraph كامل | — | نفس مخطط `graph.*` أعلاه |

**`ViewportV1`:**

| المسار | النوع | الوحدة | القيد |
| --- | --- | --- | --- |
| `ViewportV1.width` | int | px | > 0؛ ≤ `graph.profile.width` |
| `ViewportV1.height` | int | px | > 0؛ ≤ `graph.profile.height` |
| `ViewportV1.quality` | string (enum) | — | `draft` \| `standard` |
| `ViewportV1.include_audio` | bool | — | `false` في وضع `scrub` (يُفرض) |

**رد `preview_open` (Worker → Core):**

| المسار | النوع | الوحدة | القيد |
| --- | --- | --- | --- |
| `preview_open_response.session_id` | string (uuidv7) | — | نفس المعرّف الوارد |
| `preview_open_response.stream_url` | string (http) | — | loopback فقط؛ يُقرأ بـ `GET` chunked |
| `preview_open_response.frame_url_template` | string (http) | — | يحتوي `{tick}` حرفياً ليُستبدل |
| `preview_open_response.duration_ticks` | int | ticks | طول `graph.range` |
| `preview_open_response.audio` | bool | — | هل الـ stream يحمل صوتاً |
| `preview_open_response.profile.width` | int | px | دقة الـ stream الفعلية |
| `preview_open_response.profile.height` | int | px | — |
| `preview_open_response.profile.fps_num` | int | — | معدل الإطارات الفعلي |
| `preview_open_response.profile.fps_den` | int | — | — |

**رسالة `preview_cmd` (Core → Worker) — seek/play/pause/close:**

| المسار | النوع | الوحدة | إلزامي | القيد / الدلالة |
| --- | --- | --- | --- | --- |
| `preview_cmd_request.session_id` | string (uuidv7) | — | نعم | جلسة مفتوحة؛ معرّف غير معروف = `reject{code:"PREVIEW_UNKNOWN"}` |
| `preview_cmd_request.op` | string (enum) | — | نعم | `seek` \| `play` \| `pause` \| `close` |
| `preview_cmd_request.tick` | int \| null | ticks | لا (لـ `seek` فقط) | مطلوب مع `seek`، ويُتجاهل مع غيرها |
| `preview_cmd_ack.session_id` | string (uuidv7) | — | نعم | نفس المعرّف |
| `preview_cmd_ack.op` | string (enum) | — | نعم | صدى للعملية |
| `preview_cmd_ack.state` | string (enum) | — | نعم | `seeking` \| `playing` \| `paused` \| `closed` |
| `preview_cmd_ack.rendered_tick` | int \| null | ticks | لا | آخر tick أُنتج فعلاً؛ null عند `close` |

**قاعدة الـ seek:** يُلغي أي seek سابق غير مكتمل (last-write-wins)، ويُعاد الـ ack **قبل** اكتمال الرسم ليتمكن الـ Core من القياس؛ الإطار يُطلب بعدها من `frame_url_template`. لا تجزئة للـ seek في v1.

**رسالة `render_cancel` (Core → Worker):**

| المسار | النوع | الوحدة | القيد |
| --- | --- | --- | --- |
| `render_cancel_request.job_id` | string (uuidv7) | — | يجب أن يكون مهمة نشطة في هذا الـ worker؛ يُلغى الرسم خلال ≤ 500 ms ويُحذف `.part` |

**رسالة `render_start` (Core → Worker):**

| المسار | النوع | الوحدة | القيد |
| --- | --- | --- | --- |
| `render_start_request.job_id` | string (uuidv7) | — | = `render_jobs.id` |
| `render_start_request.progress_interval_ms` | int | ms | `50..2000`؛ الافتراضي 250 |
| `render_start_request.graph` | RenderGraph كامل | — | snapshot عند `project_revision` |
| `render_start_request.preset` | object (`RenderPresetV1`) | — | يُترجم إلى إعدادات الـ encoder |
| `render_start_request.output.uri` | string (file://) | — | مسار نهائي؛ الكتابة إلى `<name>.part` ثم rename |
| `render_start_request.output.overwrite` | bool | — | `false` + ملف موجود = رفض `OUTPUT_EXISTS` |

**`RenderPresetV1`:**

| المسار | النوع | الوحدة | القيد |
| --- | --- | --- | --- |
| `RenderPresetV1.container` | string (enum) | — | `mp4` \| `webm` \| `wav` \| `mp3` \| `gif` |
| `RenderPresetV1.video_codec` | string \| null | — | `h264` \| `hevc` \| `vp9` \| `gif`؛ null للتسجيلات الصوتية |
| `RenderPresetV1.audio_codec` | string \| null | — | `aac` \| `opus` \| `pcm_s16le` \| `mp3`؛ null لـ `gif` |
| `RenderPresetV1.width` | int \| null | px | null = استخدام `graph.profile.width` |
| `RenderPresetV1.height` | int \| null | px | null = استخدام `graph.profile.height` |
| `RenderPresetV1.fps_num` | int \| null | — | null = `graph.timebase.fps_num` |
| `RenderPresetV1.fps_den` | int \| null | — | null = `graph.timebase.fps_den` |
| `RenderPresetV1.video_bitrate_kbps` | int \| null | kbps | مع `crf=null`؛ أحدهما إلزامي عند وجود فيديو |
| `RenderPresetV1.crf` | int \| null | — | `0..51`؛ مع `video_bitrate_kbps` = رفض |
| `RenderPresetV1.audio_bitrate_kbps` | int \| null | kbps | `64..320` |
| `RenderPresetV1.faststart` | bool | — | يفعّل `moov` في المقدمة (mp4 فقط) |
| `RenderPresetV1.loudness_target_lufs` | int \| null | LUFS | `-24..-9`؛ null = بلا تطبيع |

**رد `render_start`:** `ack{job_id, accepted: bool, estimated_frames: int, warnings: string[]}`، أو `reject{job_id, code, detail}` بالقواعد في §أ.12.

**أشكال HTTP المطابقة (Contract A — للواجهة):**

`POST /api/v1/preview/sessions` — الطلب والرد:

| المسار | النوع | القيد |
| --- | --- | --- |
| `preview_http_request.sequence_id` | string | التسلسل المفتوح |
| `preview_http_request.mode` | string | `play` \| `scrub` |
| `preview_http_request.start_tick` | int | داخل التسلسل |
| `preview_http_request.viewport` | object (`ViewportV1`) | مطلوب |
| `preview_http_response.session_id` | string | للمسارات التالية |
| `preview_http_response.mode` | string | كما طُلب |
| `preview_http_response.stream_url` | string | fMP4 لـ `play` |
| `preview_http_response.frame_url_template` | string | JPEG لـ `scrub` |
| `preview_http_response.duration_ticks` | int | — |
| `preview_http_response.audio` | bool | — |
| `preview_http_response.profile.width` | int | — |
| `preview_http_response.profile.height` | int | — |
| `preview_http_response.profile.fps_num` | int | — |
| `preview_http_response.profile.fps_den` | int | — |

`POST /api/v1/render/jobs` — الطلب والرد:

| المسار | النوع | القيد |
| --- | --- | --- |
| `render_http_request.sequence_id` | string | — |
| `render_http_request.project_revision` | int | يجب أن يساوي `projects.revision` الحالية وإلا `409` |
| `render_http_request.preset` | object (`RenderPresetV1`) | — |
| `render_http_request.output_uri` | string | مسار مطلق قابل للكتابة |
| `render_http_request.range` | object (`RangeV1`) \| null | null = التسلسل كاملاً |
| `render_http_request.overwrite` | bool | الافتراضي `false` |
| `render_http_response.id` | string | = `render_jobs.id` |
| `render_http_response.state` | string | من §4.6 |
| `render_http_response.project_revision` | int | snapshot مجمّد |
| `render_http_response.progress_ppm` | int | 0..1000000 |
| `render_http_response.frames_total` | int \| null | null قبل `preparing` |
| `render_http_response.output_uri` | string | — |
| `render_http_response.created_at` | string | ISO-8601 UTC |

### أ.11 دلالات المعرّفات والـ revision وصلة العقد بالـ schema

| القاعدة | النص |
| --- | --- |
| المعرّفات | uuidv7 نصية، يولّدها Editing Core فقط؛ المحرك يعاملها كسلاسل شفافة (لا ترتيب، لا تفسير خاص) |
| ثبات المعرّف | معرّف الكيان لا يتغيّر مع التعديل؛ `clip.split` يُنشئ معرّفاً جديداً للمقطع الثاني فقط |
| `project_revision` | معلومة تتبّع؛ لا يُستخدم لقرار داخل المحرك، ولا يُقارن بقاعدة بيانات (المحرك لا يملك اتصالاً) |
| `graph_schema` | يُفحص لكل رسالة؛ يرفض `RG_SCHEMA_VERSION` عند عدم التطابق |
| `sequence_id` | للتشخيص/السجلات والـ cache namespacing؛ لا سلوك يعتمد عليه |
| الحتمية | نفس (revision, range, viewport) → نفس الـ graph بايت-ببايت؛ لذا `cache_key = blake3(canonical_json(graph))` صالح |

**جدول التطابق: كل حقل في العقد ↔ مصدره في SQLite** (كل مرجع بصيغة `<table>:<column>`؛ `—` = لا عمود، مع سبب):

| حقل العقد | المصدر | قاعدة الإسقاط |
| --- | --- | --- |
| `graph.sequence_id` | `sequences:id` | مباشر |
| `graph.timebase.*`, `graph.profile.width/height` | `sequences:frame_rate_num`, `sequences:frame_rate_den`, `sequences:sample_rate`, `sequences:channels`, `sequences:width`, `sequences:height` | مباشر (تحقق: المقاطع المحلية) |
| `graph.background_rgba` | `sequences:background` | `#RRGGBB` → `#RRGGBBAA` بإضافة `FF` |
| `graph.project_revision` | `projects:revision` | مباشر، للتتبّع فقط |
| `graph.graph_schema` | — | ثابت في الكود: `shadow.rendergraph/1` |
| `graph.range` | — | يحدده الطالب (preview viewport أو render range) |
| `graph.tracks[].id/kind/position/name/enabled` | `tracks:id`, `tracks:kind`, `tracks:position`, `tracks:name`, `tracks:enabled` | مباشر |
| `graph.tracks[].gain_mb` | `tracks:volume_db` | `round(volume_db × 1000)` |
| `graph.tracks[].pan_ppm` | `tracks:pan` | `round(pan × 1000000)` |
| `graph.tracks[].clips[].id/kind/start/duration/source_in/speed/opacity/enabled/label` | `clips:id`, `clips:kind`, `clips:timeline_start_ticks`, `clips:duration_ticks`, `clips:source_in_ticks`, `clips:speed_num`, `clips:speed_den`, `clips:opacity`, `clips:enabled`, `clips:label` | `opacity` → `round(opacity × 1000000)` |
| `graph.tracks[].clips[].asset_id/source_uri/source_hash` | `clips:asset_id` → `assets:id`, `assets:source_uri`, `assets:source_hash` | join عبر `asset_id`؛ null لمقطع `color` |
| `graph.tracks[].clips[].stream_index` | `asset_streams:stream_index` | اختيار stream يطابق `clips.kind` (أول مطابق أو المفضّل) |
| `graph.tracks[].clips[].transform.*` | `clips:transform_json` | تحويل الوحدات: scale/opacity → ppm، rotation → أرباع |
| `graph.tracks[].clips[].effects[]` | `clip_effects:*` | `param.value` من `params_json`، و`keyframes` من `keyframes_json` |
| `graph.tracks[].clips[].effects[].effect_key` | `clip_effects:effect_key` | تحقق من الـ registry؛ لا يُترجم إلى اسم خدمة محرك في العقد |
| `graph.tracks[].transitions[].*` | `transitions:id`, `transitions:boundary_ticks`, `transitions:duration_ticks`, `transitions:transition_key`, `transitions:params_json` | `at_ticks` = `boundary_ticks`؛ `kind` من `transition_key` عبر الـ registry |
| `graph.tracks[].text_layers[].id/start/duration` | `text_overlays:id`, `text_overlays:timeline_start_ticks`, `text_overlays:duration_ticks` | مباشر |
| `graph.tracks[].text_layers[].raster_*` | `derived_media:path`, `derived_media:cache_key`, `derived_media:width`, `derived_media:height` | للصف `kind='text_raster'` المطابق؛ `cache_key` = blake3 للمحتوى |
| `graph.tracks[].text_layers[].animation_*` | `text_overlays:animation_in_key`, `text_overlays:animation_out_key`, `text_overlays:params_json` | `none` عند null |
| `graph.tracks[].audio_clips[].*` | `clips:*` (نفس أعمدة الفيديو) | `gain_mb` ← `clips:volume_db`؛ `fade_*` ← `clips:mix_json` |
| `render_start_request.preset.*`, `output.*` | `render_jobs:preset_json`, `render_jobs:output_uri` | مباشر |
| `render_http_response.state` | `render_jobs:state` | مباشر (نفس قائمة §4.6) |
| `render_http_response.progress_ppm` | `render_jobs:progress` | `round(progress × 1000000)` |
| `render_http_response.frames_total` | `render_jobs:frames_total` | مباشر؛ null قبل `preparing` |
| `render_http_response.created_at` | `render_jobs:created_at` | ISO-8601 UTC |
| `preview_open_response.*` | — | حالة جلسة في الذاكرة فقط (لا صف في القاعدة) |

**قواعد إسقاط ملزمة:**

1. لا يُرسل أي حقل من العقد قيمة غير مشتقة من العمود أو القاعدة المذكورة أعلاه. أي حقل جديد يحتاج صفاً في هذا الجدول قبل إضافته للعقد.
2. الاتجاه واحد: الوثيقة → الـ graph. لا يقرأ المحرك الوثيقة ولا يكتب فيها.
3. `—` لا تعني "قيمة عشوائية": تعني ثابتاً أو حالة جلسة موثّقة في الصف نفسه.

### أ.12 قواعد الرفض (Validation rules) — ما يرفضه Media Core

| # | الكود | الشرط | التصرف |
| --- | --- | --- | --- |
| V-01 | `RG_SCHEMA_VERSION` | `graph_schema ≠ shadow.rendergraph/1` | رفض فوري، بلا محاولة تفسير |
| V-02 | `RG_TIMEBASE_INVALID` | `ticks_per_second ≠ 1e6`، أو `fps_num/den ≤ 0`، أو `fps > 120`، أو `sample_rate` خارج القائمة | رفض |
| V-03 | `RG_UNSUPPORTED_PROFILE` | `interlaced=true`، أو أبعاد فردية مع `yuv420p`، أو `color_space` غير مدعوم | رفض |
| V-04 | `RG_RANGE_INVALID` | `range.duration_ticks ≤ 0`، أو أي مقطع/طبقة نص خارج `[start, start+duration)` | رفض |
| V-05 | `RG_TRACK_POSITION` | `position` مكرر أو غير متواصل `0..n-1` | رفض |
| V-06 | `RG_TRACK_KIND_FIELD` | حقول لا تطابق نوع المسار (مثل `audio_clips` على `video`، أو `effects` على مسار صوتي) | رفض |
| V-07 | `RG_CLIP_OVERLAP` | مقطعان متداخلان زمنياً على نفس المسار | رفض |
| V-08 | `RG_CLIP_BOUNDS` | `duration_ticks ≤ 0`، `timeline_start_ticks < 0`، `source_in_ticks < 0`، `speed ≤ 0` | رفض |
| V-09 | `RG_MISSING_SOURCE` | `kind` يحتاج مصدراً و`source_uri`/`source_hash` غائب، أو الملف غير موجود، أو الـ hash لا يطابق | رفض (render) / `ENGINE_DEGRADED` (preview) |
| V-10 | `RG_SOURCE_TOO_SHORT` | `source_in_ticks + duration_ticks × speed > مدة المصدر + إطار` | رفض |
| V-11 | `RG_UNKNOWN_EFFECT` | `effect_key` غير موجود في `capabilities`، أو لا يبدأ بـ `shadow.` | رفض (لا fallback صامت) |
| V-12 | `RG_UNKNOWN_PARAM` | اسم param غير معلن للـ effect، أو نوعه لا يطابق `type` | رفض |
| V-13 | `RG_KEYFRAME_ORDER` | keyframes غير تصاعدية تماماً، أو خارج نطاق المقطع | رفض |
| V-14 | `RG_TRANSITION_BOUNDARY` | `at_ticks` لا يطابق نهاية `from_clip_id` وبداية `to_clip_id`، أو المدتان لا تتقاطعان بما يكفي | رفض |
| V-15 | `RG_TEXT_RASTER` | `raster_uri` غير مقروء، أو `raster_hash` لا يطابق، أو الأبعاد المعلنة لا تطابق الملف | رفض |
| V-16 | `RG_UNKNOWN_FIELD` | حقل غير معلن في هذا الملحق (بما فيه أي حقل يبدأ بـ `mlt`) | رفض صريح، لا تجاهل |
| V-17 | `RG_LIMITS` | تجاوز حدود §أ.13 | رفض |
| V-18 | `RG_PRESET_CONFLICT` | `crf` و`video_bitrate_kbps` معاً، أو codec/container غير متوافق، أو preset صوتي بلا `audio_codec` | رفض |

### أ.13 الحدود (Limits — تُفحص قبل أي عمل)

| البند | الحد |
| --- | --- |
| عدد المسارات | 32 |
| مقاطع لكل مسار | 2000 |
| effects لكل مقطع | 16 |
| params لكل effect | 32 |
| keyframes لكل param | 240 |
| طبقات نص | 200 |
| حجم الـ graph (MessagePack) | 4 MiB |
| طول `range` | 6 ساعات |

### أ.14 مثال مصغّر (المثال الكامل المتحقَّق منه في الملف)

```json
{
  "graph_schema": "shadow.rendergraph/1",
  "sequence_id": "0198f3b2-7c41-7f0a-9a1e-3d1c2b4a5e60",
  "project_revision": 218,
  "timebase": { "ticks_per_second": 1000000, "fps_num": 30000, "fps_den": 1001,
                "sample_rate": 48000, "channels": 2 },
  "profile": { "width": 1920, "height": 1080, "pixel_format": "yuv420p",
               "color_space": "bt709", "interlaced": false },
  "range": { "start_ticks": 0, "duration_ticks": 10000000 },
  "background_rgba": "#000000FF",
  "tracks": [
    { "id": "0198f3b2-9000-7000-8000-000000000001", "kind": "video", "position": 0,
      "name": "V1", "enabled": true,
      "clips": [
        { "id": "0198f3b3-0001-7000-8000-0000000000a1",
          "asset_id": "0198f3b2-b000-7000-8000-0000000000aa", "kind": "video",
          "source_uri": "file:///media/user/broll/intro-4k.mp4",
          "source_hash": "9f2c1d4e5a6b7c8d9e0f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f",
          "stream_index": 0, "timeline_start_ticks": 0, "duration_ticks": 4000000,
          "source_in_ticks": 500000, "speed_num": 1, "speed_den": 1,
          "opacity_ppm": 1000000, "enabled": true, "label": "intro",
          "transform": { "x_px": 0, "y_px": 0, "scale_x_ppm": 1000000, "scale_y_ppm": 1000000,
                         "rotation_quarter_turns": 0, "anchor": "center",
                         "crop_left_px": 0, "crop_right_px": 0, "crop_top_px": 0, "crop_bottom_px": 0 },
          "effects": [] } ] },
    { "id": "0198f3b2-9000-7000-8000-000000000003", "kind": "audio", "position": 2,
      "name": "A1", "enabled": true, "gain_mb": 0, "pan_ppm": 0,
      "audio_clips": [
        { "id": "0198f3b6-0001-7000-8000-0000000000f1",
          "asset_id": "0198f3b2-b000-7000-8000-0000000000ac",
          "source_uri": "file:///media/user/audio/vo-take3.wav",
          "source_hash": "7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e",
          "stream_index": 0, "timeline_start_ticks": 0, "duration_ticks": 10000000,
          "source_in_ticks": 0, "speed_num": 1, "speed_den": 1,
          "gain_mb": -3000, "fade_in_ticks": 200000, "fade_out_ticks": 400000,
          "enabled": true } ] }
  ]
}
```

### أ.15 ما لا يحتويه العقد (قائمة سلبية)

| غير موجود | السبب |
| --- | --- |
| أي اسم خدمة/مُعامل من MLT (`mlt_service`, `tractor`, `producer`) | المحرك يُشتق ذلك داخلياً من `effect_key`/`kind`؛ ظهوره = `RG_UNKNOWN_FIELD` |
| نص الطبقات أو الخطوط | الرسم يحدث في Core/Media قبل الـ graph؛ العقد يحمل rasters فقط (§4.4) |
| `undo` أو تاريخ التعديلات | خارج اختصاص المحرك تماماً |
| حالة المهمة/التقدّم | خارج الـ graph؛ تأتي عبر قناة `event` |
| إعدادات المشروع (snapping، autosave) | ليست وسائط |
| مسارات كاش المشروع أو مجلداته | العقد يحمل مسارات ملفات نهائية فقط |

---

## ملحق ب — قاموس سريع

| المصطلح | التعريف |
| --- | --- |
| **RenderGraph** | تمثيل محايد للمحرك لما يجب تركيبه في مدى زمني؛ لا يعرف المشروع |
| **EditCommand** | دالة خالصة: وثيقة → وثيقة + inverse + أحداث |
| **EditTransaction** | batch ذرّي من الأوامر = خطوة undo واحدة = revision واحد |
| **Proposal** | مخرج AI غير مُطبَّق؛ يحتاج قبول المستخدم وتحقّق revision |
| **Derived** | ملف ناتج قابل للحذف وإعادة البناء |
| **Degraded** | النظام يعمل بلا أحد المكونات (GPU، AI، proxy) مع إشعار |

## ملحق ج — قرارات معمارية مختصرة (ADR Index)

| ADR | القرار | البديل المرفوض |
| --- | --- | --- |
| ADR-001 | Preview كـ HTTP stream بدل FFI/Texture | ربط Flutter بـ MLT |
| ADR-002 | Document immutable + command log | ORM قابل للتعديل المباشر |
| ADR-003 | Media Core عديم الحالة يستقبل RenderGraph | Media Core يقرأ قاعدة البيانات |
| ADR-004 | Text rasterization في Media Core | الاعتماد على qtext/pango أو Flutter text |
| ADR-005 | undo بمؤشر على سجل append-only | كتابة ops معاكسة لكل undo |
| ADR-006 | AI ينتج Proposals فقط | AI يطبّق تعديلات مباشرة |
| ADR-007 | لا snapshots في v1 | snapshot كل 50 عملية |
| ADR-008 | SQLite كملف واحد للمشروع | قاعدة بيانات مركزية |

---

## ملحق د — عقود الـ IPC والـ HTTP المتبقية (wire contract v1)

هذا الملحق **معياري** ويكمل الملحق أ: كل رسالة أو نقطة نهاية مذكورة في §2.3 و§5.3 و§6.3 ولم تُعرَّف في الملحق أ تُعرَّف هنا حقلاً بحقل. **لا قاعدة جديدة**: يُعاد استخدام إطار الملحق أ (§أ.1)، وticks الصحيحة (١/1,000,000s)، والكميات المُقاسة بأعداد صحيحة (`ppm`, `millibel`, `microusd`)، ومنع أي اسم من `mlt` على الـ wire، وكون Media Core عديم الحالة. الأسئلة التي لم يُحسم لها قرار تبقى في §9، لا تُحسم هنا.

### د.1 الإطار والعقد المشترك للأخطاء والإلغاء

كل رسالة IPC تحمل إطار §أ.1 بحروفه (`protocol_version`, `message_id`, `correlation_id`, `type`, `sent_at_unix_ms`, `body`)، بما فيها رسائل هذا الملحق. قواعد إضافية:

| القاعدة | النص |
| --- | --- |
| مطابقة الطلب والرد | `correlation_id` في الرد = نفسه في الطلب؛ أي رد بـ `correlation_id` مجهول يُهمل ويُسجّل |
| رفض غير قابل للاستمرار | رسالة `reject` تحمل `ipc_error`؛ بعدها إما تُغلق القناة (أخطاء البروتوكول) أو تستمر الجلسة (أخطاء مهمة واحدة) |
| إعادة المحاولة | لا يعيد الـ worker المحاولة أبداً؛ core هو من يقرر حسب `retryable` |
| ما لا يُمرَّر على الـ wire | لا مسارات قاعدة بيانات، ولا JSON للـ document، ولا أسماء خدمات محرك، ولا نص طبقات (§4.4) |

| المسار | النوع | الوحدة | إلزامي | القيد / الدلالة |
| --- | --- | --- | --- | --- |
| `ipc_error.code` | string (enum) | — | نعم | من نفس تصنيف §7.3 (`ENGINE_*`, `MEDIA_*`, `RESOURCE_*`, `VALIDATION_*`, `CANCELLED`)؛ لا كود خاص بـ IPC |
| `ipc_error.category` | string (enum) | — | نعم | `protocol` \| `validation` \| `media` \| `engine` \| `resource` \| `internal` |
| `ipc_error.detail` | string | — | نعم | نص تشخيصي إنجليزي للـ logs فقط؛ الواجهة لا تعرضه |
| `ipc_error.retryable` | bool | — | نعم | `true` = يصح إعادة الطلب بلا تغيير؛ لا يتجاوز محاولتين |
| `ipc_error.job_id` | string \| null | uuid | لا | يُملأ إن كان الخطأ متعلقاً بمهمة |
| `ipc_error.context` | object | — | نعم | حقول مسطحة صغيرة (frame، exit_code، path)؛ لا أسرار ولا tokens |

**خرائط حرة (object_open):** ثلاثة حقول فقط تُعلن كهذه — `ipc_error.context` و`ai_submit_request.options` و`problem_dto.context` — لأن مفاتيحها تتبع الكود المطروح لا شكل ثابت. قيودها ملزمة: قيم مسطحة فقط (رقم/نص/بوليان، بلا تداخل أعمق من مستوى)، وحظر الأسرار والمسارات الشخصية وtokens. أي حقل دلالي (يؤثر على السلوك) لا يجوز أن يكون داخلها؛ يجب أن يأخذ صفاً صريحاً في هذا الملحق.

**انتشار الإلغاء (ملزم للثلاث طبقات):**

```
UI: POST /render/jobs/{id}/cancel
  → Core: validate state (terminal ⇒ 409 CONFLICT_JOB_TERMINAL)
  → Core: يكتب state=cancelled + finished_at في نفس txn، ثم يرسل IPC cancel
  → Worker: يوقف عند أقرب حد إطار (≤ 500 ms)، يحذف .part، يردّ ack
  → Core: job_event(terminal) + WS render.state
```

1. الإلغاء **idempotent**: تكراره على مهمة ملغاة يعيد 200 بنفس الحالة، لا خطأ.
2. إذا كان الـ worker غير قابل للوصول: تُعلَّم المهمة `cancelled` مع `error_code = ENGINE_UNREACHABLE` — لأن الحقيقة الدائمة هي سجل Core، والمحرك بلا حالة.
3. بعد `cancelled` لا يُقبل أي `job_event` لنفس `job_id`؛ يُسجّل ويُهمل.

### د.2 رسائل IPC المتبقية

#### د.2.1 `hello` / `hello_ack`

| المسار | النوع | الوحدة | إلزامي | القيد |
| --- | --- | --- | --- | --- |
| `hello_request.protocol_version` | int | revision | نعم | إصدار Core؛ يُقارن بـ `min_supported` |
| `hello_request.min_supported` | int | revision | نعم | أقل إصدار يقبله Core؛ `min ≤ protocol_version` |
| `hello_request.engine_version` | string | — | نعم | نص حر للـ logs |
| `hello_request.capabilities.filters` | array of string | — | نعم | مفاتيح `shadow.*` المتاحة؛ لا أسماء `mlt` |
| `hello_request.capabilities.transitions` | array of string | — | نعم | من تعداد §أ.7 |
| `hello_request.capabilities.containers` | array of string | — | نعم | من تعداد `RenderPresetV1` |
| `hello_request.capabilities.video_codecs` | array of string | — | نعم | من تعداد `RenderPresetV1` |
| `hello_request.capabilities.audio_codecs` | array of string | — | نعم | من تعداد `RenderPresetV1` |
| `hello_ack.protocol_version` | int | revision | نعم | الإصدار المُتفق عليه = `1` حالياً |
| `hello_ack.engine_version` | string | — | نعم | إصدار المحرك كما يراه الـ worker |
| `hello_ack.accepted` | bool | — | نعم | `false` يستوجب `ipc_error{code:PROTOCOL_MISMATCH}` في نفس الرد |

#### د.2.2 `probe`

| المسار | النوع | الوحدة | إلزامي | القيد |
| --- | --- | --- | --- | --- |
| `probe_request.path` | string (file://) | — | نعم | مسار مطلق؛ الـ worker يفتحه read-only ولا يكتب بجانبه |
| `probe_request.timeout_ms` | int | ms | نعم | `1000..60000`؛ timeout ⇒ `ENGINE_TIMEOUT` |
| `probe_request.want_thumbnail` | bool | — | نعم | `true` = يُدرج طلب `ensure_derived(kind=thumbnail)` ضمنياً |
| `probe_result.asset_hash` | string (64 hex) | blake3 | نعم | يُحسب في Core قبل الطلب ويُتحقق منه الـ worker |
| `probe_result.size_bytes` | int | bytes | نعم | > 0 |
| `probe_result.duration_ticks` | int | ticks | نعم | > 0؛ مصدر الحقيقة لـ `assets.duration_ticks` |
| `probe_result.streams` | array of `ProbeStreamV1` | — | نعم | فهرس متصل `0..n-1` |
| `probe_result.warnings` | array of string | — | نعم | أكواد مثل `MEDIA_VFR_NORMALIZED`؛ `[]` مسموح |

**`ProbeStreamV1`** (يُستخدم في `probe_result.streams` و`asset_dto.streams`):

| المسار | النوع | الوحدة | القيد |
| --- | --- | --- | --- |
| `ProbeStreamV1.index` | int | index | فريد داخل الأصل |
| `ProbeStreamV1.media_type` | string (enum) | — | `video` \| `audio` \| `subtitle` \| `data` |
| `ProbeStreamV1.codec` | string (enum) | — | `h264` \| `hevc` \| `vp9` \| `av1` \| `prores` \| `aac` \| `opus` \| `pcm_s16le` \| `pcm_s24le` \| `mp3` |
| `ProbeStreamV1.width` | int \| null | px | مطلوب لـ `video`، null لغيرها |
| `ProbeStreamV1.height` | int \| null | px | مطلوب لـ `video` |
| `ProbeStreamV1.fps_num` | int \| null | ratio | مطلوب لـ `video` |
| `ProbeStreamV1.fps_den` | int \| null | ratio | مطلوب لـ `video` |
| `ProbeStreamV1.sample_rate` | int \| null | Hz | مطلوب لـ `audio` |
| `ProbeStreamV1.channels` | int \| null | count | مطلوب لـ `audio` |
| `ProbeStreamV1.bit_depth` | int \| null | bit | null إن كان غير معروفاً |
| `ProbeStreamV1.rotation` | int | count | `0..3` (أرباع دورة) |
| `ProbeStreamV1.start_ticks` | int | ticks | ≥ 0 |
| `ProbeStreamV1.duration_ticks` | int | ticks | > 0 |
| `ProbeStreamV1.language` | string \| null | — | BCP-47؛ null = غير معلن |

#### د.2.3 `ensure_derived`

| المسار | النوع | الوحدة | إلزامي | القيد |
| --- | --- | --- | --- | --- |
| `ensure_derived_request.cache_key` | string (64 hex) | blake3 | نعم | مفتاح الكاش من §7.2؛ نفس المفتاح = لا إعادة ترميز |
| `ensure_derived_request.kind` | string (enum) | — | نعم | `proxy` \| `thumbnail` \| `sprite` \| `waveform` \| `text_raster` |
| `ensure_derived_request.source_uri` | string (file://) | — | نعم | الأصل أو raster المصدر |
| `ensure_derived_request.source_hash` | string (64 hex) | blake3 | نعم | تحقق قبل القراءة |
| `ensure_derived_request.priority` | int | index | نعم | `0..9` (0 أعلى)؛ preview يتجاوز derived دائماً |
| `ensure_derived_request.target_width` | int \| null | px | لا | مطلوب لـ `proxy`؛ null لغيره |
| `ensure_derived_request.target_height` | int \| null | px | لا | مطلوب لـ `proxy` |
| `ensure_derived_request.target_fps_num` | int \| null | ratio | لا | null = معدل المصدر |
| `ensure_derived_request.target_fps_den` | int \| null | ratio | لا | null = معدل المصدر |
| `ensure_derived_result.cache_key` | string (64 hex) | blake3 | نعم | صدى للمفتاح |
| `ensure_derived_result.path` | string (file://) | — | نعم | ملف تام (بعد rename ذرّي) |
| `ensure_derived_result.bytes` | int | bytes | نعم | > 0 |
| `ensure_derived_result.width` | int \| null | px | لا | لأبعاد الناتج |
| `ensure_derived_result.height` | int \| null | px | لا | — |
| `ensure_derived_result.duration_ticks` | int \| null | ticks | لا | null للـ raster |

#### د.2.4 `job_status` و`job_cancel` و`health` و`event`

| المسار | النوع | الوحدة | إلزامي | القيد |
| --- | --- | --- | --- | --- |
| `job_status_request.job_id` | string (uuidv7) | — | نعم | معرّف المهمة كما يعرفه Core |
| `job_status_request.kind` | string (enum) | — | نعم | `render` \| `derived` \| `preview` |
| `job_status_result.job_id` | string (uuidv7) | — | نعم | نفس المعرّف |
| `job_status_result.kind` | string (enum) | — | نعم | كما طُلب |
| `job_status_result.state` | string (enum) | — | نعم | من `job_state` (§د.5) |
| `job_status_result.progress_ppm` | int | ppm | نعم | `0..1000000`؛ غير تنازلي داخل المهمة |
| `job_status_result.frames_done` | int | count | نعم | 0 للمهام غير الإطارية |
| `job_status_result.frames_total` | int \| null | count | لا | null قبل `preparing` |
| `job_status_result.rendered_tick` | int \| null | ticks | لا | لـ preview فقط |
| `job_status_result.error_code` | string \| null | enum | لا | مطلوب إن `state=failed` |
| `job_status_result.error_detail` | string \| null | — | لا | للتشخيص فقط |
| `derived_cancel_request.cache_key` | string (64 hex) | blake3 | نعم | إلغاء بناء derived جارٍ |
| `derived_cancel_ack.cache_key` | string (64 hex) | blake3 | نعم | صدى |
| `derived_cancel_ack.cancelled` | bool | — | نعم | `false` = كان منتهياً بالفعل (idempotent) |
| `health_result.ok` | bool | — | نعم | `false` = لا تُرسل مهام جديدة |
| `health_result.engine_version` | string | — | نعم | — |
| `health_result.protocol_version` | int | revision | نعم | — |
| `health_result.gpu_present` | bool | — | نعم | معلومة قائمة فقط؛ v1 لا يستخدمها للترميز |
| `health_result.degraded` | array of string | — | نعم | مثلاً `preview_hw_decode`؛ `[]` = كل شيء سليم |
| `health_result.active_jobs` | int | count | نعم | ≥ 0؛ للسعة والـ backpressure |
| `job_event.job_id` | string (uuidv7) | — | نعم | مهمة معروفة |
| `job_event.kind` | string (enum) | — | نعم | `render` \| `derived` \| `preview` |
| `job_event.type` | string (enum) | — | نعم | `progress` \| `state` \| `log` |
| `job_event.progress_ppm` | int \| null | ppm | لا | مطلوب لـ `progress` |
| `job_event.frames_done` | int \| null | count | لا | — |
| `job_event.rendered_tick` | int \| null | ticks | لا | لـ preview |
| `job_event.state` | string \| null | enum | لا | مطلوب لـ `state` |
| `job_event.error_code` | string \| null | enum | لا | عند `state=failed` |

**قاعدة الاشتراك:** لا يوجد `subscribe` على قناة الـ IPC؛ الأحداث تصل لكل المهام النشطة على نفس الاتصال، وتُرشَّح في Core. هذا يُبقي المحرك عديم الحالة ويُلغي حاجة لمزامنة اشتراكات مع إعادة تشغيل worker.

### د.3 المشروع: create / open / save / close

| المسار | النوع | الوحدة | إلزامي | القيد |
| --- | --- | --- | --- | --- |
| `project_create_request.name` | string | — | نعم | `1..200` حرفاً بعد trim |
| `project_create_request.location_dir` | string \| null | file:// | لا | null = آخر مجلد مستخدم |
| `project_create_request.profile.width` | int | px | نعم | > 0 وزوجي |
| `project_create_request.profile.height` | int | px | نعم | > 0 وزوجي |
| `project_create_request.profile.fps_num` | int | ratio | نعم | > 0 |
| `project_create_request.profile.fps_den` | int | ratio | نعم | > 0؛ `fps ≤ 120` |
| `project_create_request.profile.sample_rate` | int | Hz | نعم | `44100` \| `48000` \| `96000` |
| `project_create_request.profile.channels` | int | count | نعم | `1..8` |
| `project_dto.id` | string (uuidv7) | — | نعم | `projects.id` |
| `project_dto.name` | string | — | نعم | — |
| `project_dto.revision` | int | revision | نعم | `projects.revision`؛ يبدأ من 0 |
| `project_dto.schema_version` | int | revision | نعم | `projects.schema_version` |
| `project_dto.path` | string (file://) | — | نعم | ملف `.ssproj` (SQLite) |
| `project_dto.created_at` | string | ISO-8601 | نعم | UTC بـ `Z` |
| `project_dto.updated_at` | string | ISO-8601 | نعم | UTC بـ `Z` |
| `project_dto.profile.width` | int | px | نعم | من `sequences`/`projects` |
| `project_dto.profile.height` | int | px | نعم | — |
| `project_dto.profile.fps_num` | int | ratio | نعم | — |
| `project_dto.profile.fps_den` | int | ratio | نعم | — |
| `project_dto.profile.sample_rate` | int | Hz | نعم | — |
| `project_dto.profile.channels` | int | count | نعم | — |
| `project_dto.sequence_count` | int | count | نعم | ≥ 1 في v1 |
| `project_open_request.path` | string (file://) | — | نعم | يجب أن يكون ملفاً موجوداً وقابلاً للكتابة |
| `project_save_result.revision` | int | revision | نعم | يجب أن يساوي `projects.revision` بعد الـ flush |
| `project_save_result.saved_at` | string | ISO-8601 | نعم | UTC |
| `project_save_result.snapshot_bytes` | int | bytes | نعم | حجم الملف بعد checkpoint؛ للتشخيص |
| `project_close_request.flush` | bool | — | نعم | `true` = flush + WAL checkpoint قبل الإغلاق |

**قواعد المشروع:** مشروع واحد مفتوح لكل Core instance (OQ-8 افتراضياً). `POST /projects/open` أثناء فتح مشروع آخر ⇒ `409 CONFLICT_PROJECT_ALREADY_OPEN`. و`/project/save` لا يغيّر `revision` (الحفظ ليس تعديلاً).

### د.4 الاستيراد والوسائط

| المسار | النوع | الوحدة | إلزامي | القيد |
| --- | --- | --- | --- | --- |
| `import_request.paths` | array of string (file://) | — | نعم | `1..200` مساراً؛ كلها مطلقة |
| `import_request.options.proxy_policy` | string (enum) | — | نعم | `auto` \| `never` \| `always` (سياسة §4.2) |
| `import_request.options.generate_thumbnails` | bool | — | نعم | — |
| `import_request.options.generate_waveform` | bool | — | نعم | — |
| `import_accepted.import_id` | string (uuidv7) | — | نعم | معرّف الدفعة؛ حالة في الذاكرة + `job_events(job_kind='import')` |
| `import_accepted.accepted` | array of string (file://) | — | نعم | المسارات المقبولة فوراً؛ قد تكون `[]` |
| `import_accepted.rejected` | array of object | — | نعم | رفض فوري (غير موجود/غير مدعوم)؛ `[]` مسموح |
| `import_accepted.submitted_at` | string | ISO-8601 | نعم | UTC |
| `import_accepted.rejected[].path` | string (file://) | — | نعم | المسار المرفوض |
| `import_accepted.rejected[].code` | string (enum) | — | نعم | `MEDIA_UNSUPPORTED` \| `MEDIA_NOT_FOUND` \| `VALIDATION_PATH_NOT_ABSOLUTE` |
| `import_status_dto.import_id` | string (uuidv7) | — | نعم | نفس المعرّف |
| `import_status_dto.state` | string (enum) | — | نعم | من `job_state` |
| `import_status_dto.progress_ppm` | int | ppm | نعم | `0..1000000` |
| `import_status_dto.assets` | array of object | — | نعم | يُملأ تدريجياً؛ `[]` قبل أول probe |
| `import_status_dto.started_at` | string | ISO-8601 | نعم | — |
| `import_status_dto.finished_at` | string \| null | ISO-8601 | لا | null حتى الحالة النهائية |
| `import_status_dto.assets[].asset_id` | string (uuidv7) | — | نعم | `assets.id` |
| `import_status_dto.assets[].path` | string (file://) | — | نعم | — |
| `import_status_dto.assets[].status` | string (enum) | — | نعم | `probing` \| `derived_pending` \| `ready` \| `failed` |
| `import_status_dto.assets[].code` | string \| null | enum | لا | مطلوب إن `failed` |
| `asset_dto.id` | string (uuidv7) | — | نعم | `assets.id` |
| `asset_dto.kind` | string (enum) | — | نعم | `video` \| `audio` \| `image` \| `ai_generated` |
| `asset_dto.display_name` | string | — | نعم | — |
| `asset_dto.source_uri` | string (file://) | — | نعم | — |
| `asset_dto.source_hash` | string (64 hex) | blake3 | نعم | — |
| `asset_dto.size_bytes` | int | bytes | نعم | > 0 |
| `asset_dto.duration_ticks` | int | ticks | نعم | > 0 |
| `asset_dto.missing` | bool | — | نعم | `true` = `assets.missing_since` غير null |
| `asset_dto.imported_at` | string | ISO-8601 | نعم | UTC |
| `asset_dto.streams` | array of `ProbeStreamV1` | — | نعم | نفس المخطط أعلاه |

### د.5 النموذج الموحّد للحالة غير المتزامنة

كل المهام (import، render، ai، derived) تتشارك تعداداً واحداً وانتقالات واحدة. هذا يمنع أربع آلات حالة متباعدة.

| `job_state` | معنى | نهائية؟ |
| --- | --- | --- |
| `queued` | مقبولة، لم تبدأ | لا |
| `running` | قيد التنفيذ (submitted/preparing/rendering كلها هنا على هذا المستوى) | لا |
| `succeeded` | اكتملت بناتج صالح | نعم |
| `failed` | فشل نهائي مع `error_code` | نعم |
| `cancelled` | ألغاها المستخدم | نعم |
| `interrupted` | انهار المنفّذ؛ قابلة لإعادة الطرح يدوياً | لا (تعود إلى `queued` مرة واحدة) |
| `expired` | نتيجة AI لم تُستلم خلال 24 ساعة (AI فقط) | نعم |

| المسار | النوع | الوحدة | إلزامي | القيد |
| --- | --- | --- | --- | --- |
| `job_status_dto.id` | string (uuidv7) | — | نعم | معرّف المهمة حسب نوعها |
| `job_status_dto.kind` | string (enum) | — | نعم | `import` \| `render` \| `ai` \| `derived` |
| `job_status_dto.state` | string (enum) | — | نعم | من `job_state` |
| `job_status_dto.progress_ppm` | int | ppm | نعم | `0..1000000`؛ `1000000` إذا وفقط إذا `succeeded` |
| `job_status_dto.frames_done` | int \| null | count | لا | لـ render فقط |
| `job_status_dto.frames_total` | int \| null | count | لا | لـ render فقط |
| `job_status_dto.error_code` | string \| null | enum | لا | إلزامي لـ `failed`، وnull لغيره |
| `job_status_dto.error_detail` | string \| null | — | لا | للتشخيص |
| `job_status_dto.created_at` | string | ISO-8601 | نعم | UTC |
| `job_status_dto.started_at` | string \| null | ISO-8601 | لا | null في `queued` |
| `job_status_dto.finished_at` | string \| null | ISO-8601 | لا | إلزامي في الحالات النهائية |
| `subscribe_request.topics` | array of string | — | نعم | `1..16`؛ من: `timeline` \| `project` \| `assets` \| `render.jobs` \| `ai.jobs` \| `ai.proposals` \| `engine` |
| `subscribe_request.since_seq` | int | count | نعم | ≥ 0؛ 0 = من البداية؛ يستخدم للـ replay بعد انقطاع WS |

**انتقالات مسموحة فقط:** `queued→running`, `running→succeeded|failed|cancelled`, `running→interrupted`, `interrupted→queued`, و`*→cancelled` من الحالات غير النهائية. أي انتقال آخر ⇒ `409 CONFLICT_JOB_TERMINAL` أو `D-04`.

**قرار جديد (مسجّل):** `GET /jobs/{id}` هو القراءة القياسية لأي مهمة، و`/render/jobs/{id}` و`/ai/jobs/{id}` تبقى موجودة كمسارات مختصرة تُرجع نفس الحقول الأساسية. البديل المرفوض: أربعة أشكال حالة منفصلة تتطوّر بشكل متباعد. سبب القرار: مصدر حقيقة واحد للـ UI.

### د.6 الذكاء الاصطناعي: submit / status / proposal / accept / failure

| المسار | النوع | الوحدة | إلزامي | القيد |
| --- | --- | --- | --- | --- |
| `ai_submit_request.capability` | string (enum) | — | نعم | `auto_cut` \| `captions` \| `audio_clean` \| `smart_reframe` \| `scene_detect` \| `transcribe` |
| `ai_submit_request.provider` | string \| null | enum | لا | null = يختار الـ router حسب §6.2؛ صريحاً يمنع failover صامتاً |
| `ai_submit_request.model` | string \| null | — | لا | null = الافتراضي عند المزوّد |
| `ai_submit_request.inputs` | array of object | — | نعم | `1..8` مدخلات |
| `ai_submit_request.options` | object | — | نعم | مفاتيح الخدمة (اللغة، التقسيم)؛ `{}` مسموح |
| `ai_submit_request.idempotency_key` | string (64 hex) | blake3 | نعم | `blake3(capability, input_hashes, options)`؛ نفس المفتاح بمحتوى مختلف ⇒ `409 CONFLICT_IDEMPOTENCY` |
| `ai_submit_request.inputs[].kind` | string (enum) | — | نعم | `asset_range` \| `text` \| `transcript` |
| `ai_submit_request.inputs[].asset_id` | string \| null | uuid | لا | إلزامي لـ `asset_range` |
| `ai_submit_request.inputs[].start_ticks` | int \| null | ticks | لا | إلزامي لـ `asset_range`؛ ≥ 0 |
| `ai_submit_request.inputs[].end_ticks` | int \| null | ticks | لا | إلزامي لـ `asset_range`؛ `> start_ticks` |
| `ai_submit_request.inputs[].text` | string \| null | — | لا | إلزامي لـ `text`؛ ≤ 64 KiB |
| `ai_job_dto.id` | string (uuidv7) | — | نعم | `ai_jobs.id` |
| `ai_job_dto.capability` | string (enum) | — | نعم | كما طُلب |
| `ai_job_dto.provider` | string (enum) | — | نعم | المزوّد الفعلي (قد يختلف عند failover) |
| `ai_job_dto.model` | string \| null | — | لا | — |
| `ai_job_dto.state` | string (enum) | — | نعم | من `job_state` + `expired` |
| `ai_job_dto.attempts` | int | count | نعم | ≥ 1 بعد أول إرسال؛ ≤ 3 |
| `ai_job_dto.progress_ppm` | int | ppm | نعم | coarse: `0` أو `500000` أو `1000000` فقط |
| `ai_job_dto.cost_microusd` | int \| null | microUSD | لا | تقدير قبل التنفيذ؛ null إن تعذّر |
| `ai_job_dto.created_at` | string | ISO-8601 | نعم | UTC |
| `ai_job_dto.updated_at` | string | ISO-8601 | نعم | UTC |
| `ai_job_dto.summary` | string \| null | — | لا | ملخص قصير للمستخدم |
| `ai_job_dto.artifacts` | array of object | — | نعم | ملفات ناتجة (WAV نظيف، رموز مشاهد)؛ `[]` مسموح |
| `ai_job_dto.error_code` | string \| null | enum | لا | `AI_NO_KEY` \| `AI_INVALID_KEY` \| `AI_QUOTA` \| `AI_RATE_LIMIT` \| `AI_TIMEOUT` \| `AI_INVALID_RESULT` \| `AI_NETWORK` \| `AI_COST_CAP` |
| `ai_job_dto.error_retryable` | bool \| null | — | لا | مطلوب مع `error_code` |
| `ai_job_dto.artifacts[].kind` | string (enum) | — | نعم | `audio` \| `image` \| `transcript` \| `scene_list` |
| `ai_job_dto.artifacts[].path` | string (file://) | — | نعم | ملف محلي (نُزّل قبل الرد) |
| `ai_job_dto.artifacts[].width` | int \| null | px | لا | للصور |
| `ai_job_dto.artifacts[].height` | int \| null | px | لا | للصور |
| `ai_job_dto.artifacts[].duration_ticks` | int \| null | ticks | لا | للصوت |
| `ai_proposal_dto.id` | string (uuidv7) | — | نعم | `ai_proposals.id` |
| `ai_proposal_dto.ai_job_id` | string (uuidv7) | — | نعم | `ai_proposals.ai_job_id` |
| `ai_proposal_dto.kind` | string (enum) | — | نعم | `cuts` \| `captions` \| `audio_clean` \| `smart_reframe` \| `markers` |
| `ai_proposal_dto.base_revision` | int | revision | نعم | `projects.revision` عند بناء المقترح |
| `ai_proposal_dto.ops_count` | int | count | نعم | ≥ 0؛ عدد عمليات التعديل التي ستُطبَّق عند القبول |
| `ai_proposal_dto.preview_start_ticks` | int | ticks | نعم | ≥ 0 |
| `ai_proposal_dto.preview_end_ticks` | int | ticks | نعم | `> preview_start_ticks` |
| `ai_proposal_dto.summary` | string \| null | — | لا | نص للمستخدم |
| `ai_proposal_dto.accepted_at` | string \| null | ISO-8601 | لا | null حتى القبول |
| `ai_accept_request.label` | string \| null | — | لا | تصنيف batch في `edit_ops.origin='ai'` للتعرّف عليه في undo |
| `ai_accept_result.proposal_id` | string (uuidv7) | — | نعم | — |
| `ai_accept_result.revision` | int | revision | نعم | `> base_revision` بعد التطبيق |
| `ai_accept_result.applied_ops` | int | count | نعم | يساوي `ops_count` عند النجاح |

**قرار جديد (مسجّل):** `progress_ppm` للـ AI لا يتجاوز ثلاث قيم (`0`، `500000`، `1000000`) لأن المزوّدين لا يعطون تقدماً حقيقياً؛ البديل المرفوض: تقدم كاذب مُقدَّر بالزمن المنقضي، وهو أسوأ من الصدق.

**مسار الفشل:** `failed` يُكتب مع `error_code` و`error_retryable`، ويظل المقترح (إن وُجد جزئياً) غير مطبّق. إذا انقطعت النتيجة بعد `expired` فلا قبول ولا تعديل (`409 CONFLICT_PROPOSAL_EXPIRED`).

### د.7 الخطأ الموحّد على HTTP

| المسار | النوع | الوحدة | إلزامي | القيد |
| --- | --- | --- | --- | --- |
| `problem_dto.type` | string (URI) | — | نعم | `https://shadow.studio/problems/<slug>` |
| `problem_dto.title` | string | — | نعم | إنجليزي قصير؛ للـ logs/الدعم |
| `problem_dto.status` | int | — | نعم | `400..599` |
| `problem_dto.code` | string (enum) | — | نعم | من تصنيف §7.3؛ الواجهة تترجم من هذا الحقل |
| `problem_dto.detail` | string | — | نعم | آمن للعرض في تقرير خطأ؛ لا stack traces |
| `problem_dto.instance` | string (URI) | — | نعم | مسار الطلب |
| `problem_dto.correlation_id` | string (uuidv7) | — | نعم | موجود في logs Core حتماً |
| `problem_dto.retryable` | bool | — | نعم | `true` = يصح للمستخدم/الواجهة إعادة المحاولة |
| `problem_dto.context` | object | — | نعم | حقول مسطحة (expected/actual/asset_id)؛ لا أسرار |

### د.8 دلالات المعرّفات والـ revision ↔ DDL

| القاعدة | النص |
| --- | --- |
| توليد المعرّفات | Core فقط، uuidv7؛ الـ worker لا يولّد معرّف كيان أبداً |
| `If-Match` | كل كتابة على المشروع تحمل `If-Match: <revision>`؛ عدم التطابق ⇒ `409 CONFLICT_REVISION_MISMATCH` مع `problem_dto.context{expected, actual}` |
| إعادة المحاولة الآمنة | `Idempotency-Key` على create/import/render/ai؛ نفس المفتاح بنفس المحتوى = نفس النتيجة بلا تنفيذ ثانٍ |
| الإصدار | `protocol_version` (IPC) و`graph_schema` (graph) يعملان كما في §أ.1؛ لا تغيير هنا |
| `import_id` | حالة جلسة في الذاكرة + صفوف `job_events`؛ لا جدول خاص (نفس قرار جلسات المعاينة) |
| `job_id` | `render_jobs.id` أو `ai_jobs.id` حسب النوع؛ موحّد في `job_status_dto` |
| `revision` في AI | `ai_proposals.base_revision` يُقارن بـ `projects.revision` عند القبول حصراً |

**جدول التطابق: حقول الملحق د ↔ SQLite** (كل مرجع بصيغة `<table>:<column>`):

| حقل العقد | المصدر | قاعدة الإسقاط |
| --- | --- | --- |
| `project_dto.*` | `projects:id`, `projects:name`, `projects:revision`, `projects:schema_version`, `projects:width`, `projects:height`, `projects:frame_rate_num`, `projects:frame_rate_den`, `projects:sample_rate`, `projects:channels`, `projects:created_at`, `projects:updated_at` | مباشر؛ `path` = مسار ملف المشروع (حالة خارج القاعدة) |
| `asset_dto.*` | `assets:id`, `assets:kind`, `assets:display_name`, `assets:source_uri`, `assets:source_hash`, `assets:size_bytes`, `assets:duration_ticks`, `assets:missing_since`, `assets:imported_at` | `missing` = `missing_since IS NOT NULL` |
| `asset_dto.streams[]`, `probe_result.streams[]` | `asset_streams:stream_index`, `asset_streams:media_type`, `asset_streams:codec`, `asset_streams:width`, `asset_streams:height`, `asset_streams:frame_rate_num`, `asset_streams:frame_rate_den`, `asset_streams:sample_rate`, `asset_streams:channels`, `asset_streams:bit_depth`, `asset_streams:rotation`, `asset_streams:start_ticks`, `asset_streams:duration_ticks`, `asset_streams:language` | مباشر |
| `ensure_derived_result.*` | `derived_media:cache_key`, `derived_media:path`, `derived_media:bytes`, `derived_media:width`, `derived_media:height`, `derived_media:duration_ticks`, `derived_media:kind` | مباشر |
| `job_status_dto.state` (render) | `render_jobs:state` | نفس التعداد بعد تسوية أسماء المراحل الداخلية |
| `job_status_dto.progress_ppm` (render) | `render_jobs:progress` | `round(progress × 1000000)` |
| `job_status_dto.frames_done`, `frames_total` | `render_jobs:frames_done`, `render_jobs:frames_total` | مباشر |
| `job_status_dto.error_code/detail` | `render_jobs:error_json` | يُقرأ منه `code`/`detail` |
| `job_status_dto.created_at/started_at/finished_at` | `render_jobs:created_at`, `render_jobs:started_at`, `render_jobs:finished_at` | مباشر |
| `ai_job_dto.*` | `ai_jobs:id`, `ai_jobs:capability`, `ai_jobs:provider`, `ai_jobs:model`, `ai_jobs:state`, `ai_jobs:attempts`, `ai_jobs:result_json`, `ai_jobs:error_json`, `ai_jobs:cost_estimate_usd`, `ai_jobs:created_at`, `ai_jobs:updated_at` | `cost_microusd = round(cost_estimate_usd × 1000000)`؛ `summary`/`artifacts` من `result_json` |
| `ai_submit_request.idempotency_key` | `ai_jobs:idempotency_key` | مباشر (UNIQUE) |
| `ai_proposal_dto.*` | `ai_proposals:id`, `ai_proposals:ai_job_id`, `ai_proposals:kind`, `ai_proposals:base_revision`, `ai_proposals:preview_json`, `ai_proposals:ops_json`, `ai_proposals:accepted_at` | `ops_count` = طول `ops_json`؛ `preview_*` و`summary` من `preview_json` |
| `job_event.*`, `import_status_dto.*` | `job_events:job_id`, `job_events:job_kind`, `job_events:type`, `job_events:payload_json` | append-only؛ تُقرأ لآخر حدث |
| `problem_dto.*` | — | يُبنى عند الرد؛ لا صف |
| `hello_*/probe_*/health_*` | — | نتائج تشغيلية لا تُخزَّن (probe يُخزَّن في `assets.probe_json` عبر Core) |

### د.9 قواعد الرفض لهذا الملحق

| # | الكود | الشرط | التصرف |
| --- | --- | --- | --- |
| D-01 | `VALIDATION_ENUM` | قيمة خارج التعداد المعلن | 422 |
| D-02 | `VALIDATION_IDEMPOTENCY` | نفس `Idempotency-Key` بمحتوى مختلف | 409 |
| D-03 | `CONFLICT_PROJECT_ALREADY_OPEN` | فتح مشروع وهناك مشروع مفتوح | 409 |
| D-04 | `CONFLICT_JOB_TERMINAL` | انتقال من حالة نهائية أو إلغاء بعدها | 409 |
| D-05 | `CONFLICT_PROPOSAL_EXPIRED` | قبول مقترح بعد `expired` أو `cancelled` | 409 |
| D-06 | `STALE_PROPOSAL` | `If-Match` لا يساوي `base_revision` | 409 |
| D-07 | `MEDIA_NOT_FOUND` | مسار غير موجود عند الاستيراد | يُدرج في `rejected[]`، لا يفشل الدفعة |
| D-08 | `VALIDATION_AI_INPUT` | `asset_range` بلا `asset_id` أو `end_ticks ≤ start_ticks` | 422 |
| D-09 | `AI_NO_KEY` | لا مفتاح مزوّد مضبوط | 400 مع CTA |
| D-10 | `AI_COST_CAP` | تجاوز السقف الشهري قبل الإرسال | 402 |
| D-11 | `VALIDATION_TOPIC` | موضوع اشتراك غير معلن | 422 |
| D-12 | `ENGINE_TIMEOUT` | `probe` تجاوز `timeout_ms` | 504 عبر Core |
| D-13 | `PROTOCOL_MISMATCH` | `hello` بلا تقاطع إصدارات | إغلاق القناة بعد `reject` |
| D-14 | `RESOURCE_QUEUE_FULL` | تجاوز حد الطوابير (§5.4) | 429 |

### د.10 ما لا يحتويه هذا الملحق (قائمة سلبية)

| غير موجود | السبب |
| --- | --- |
| أي اسم من `mlt` في أي حقل أو تعداد | نفس قاعدة الملحق أ؛ يرفض عند الحدود |
| محتوى `transcript` الكامل داخل `job_status_dto` | يُنزَّل كملف `artifacts[]`؛ الحالة تبقى صغيرة |
| تعديل المشروع عبر رسائل IPC | الذكاء والتعديل يحدثان في Core؛ المحرك لا يعرف المشروع |
| تقدّم دقيق لمهام AI | المزوّدون لا يعطونه؛ انظر القرار المسجّل في §د.6 |
| حالات فرعية مثل `encoding`/`finalizing` في العقد العام | تبقى داخل `render_jobs` وتظهر كـ `running` في `job_status_dto`؛ التفصيل لـ WS فقط |
| أسماء محرك داخل `engine_version` | استثناء وحيد ومقصود: نص بناء مبهم للتشخيص؛ لا حقل آخر قد يستخدم اسم مكوّن محرك، ولا قرار يتخذ على أساسه (يُسجّل فقط) |
| مفاتيح داخل الخرائط الحرة ترشّح سلوكاً | ممنوع: الخرائط للتشخيص والخيارات النصية فقط؛ أي مفتاح يغيّر المعالجة يجب أن يكون حقلاً معلناً |

---

## ملحق هـ — المخطط الحقلي المُلزِم للـ RenderGraph (field-level schema v1)

| الحقل | القيمة |
| --- | --- |
| Document ID | `SS-ARCH-001-ه` |
| Version | `1.0` |
| Status | **Approved** — يكمّل الملحق أ ولا ينقضه |
| مصدر الحقيقة الآلي | [`rendergraph.schema.json`](contracts/rendergraph.schema.json) + [`rendergraph.effects.json`](contracts/rendergraph.effects.json) |
| المدقّق | `validate_contract.py` (المرحلة `schema`) + `validate_schema.py` |
| النطاق | كائن `RenderGraph` كاملاً + سجل المؤثرات والانتقالات. **لا** يشمل رسائل IPC/HTTP خارج الـ graph (الملحقان أ ود) ولا `RenderPresetV1` (أ.10) |

> **لماذا ملحق خامس:** الملحق أ يجيب «أي حقول توجد»، والملحق هـ يجيب «أي **نوع** بالضبط». بلا هذا الملف، كل فريق محرك يخترع تعريفه الخاص لـ `ParamV1.value`، ومنحنى `ease_in_out`، ومعنى `1000000` في `scale_x_ppm`، ومن يملك اللقطات في نافذة الانتقال. هذه هي المواضع الأربعة التي لا يستطيع مطوّر Media Core البناء دون تخمين.

### ه.1 سلطة الوثيقة وعلاقتها بالملحق أ

| الطبقة | الدور | عند التعارض |
| --- | --- | --- |
| `rendergraph.schema.json` | التعريف النوعي المعياري (JSON Schema 2020-12، كائنات مغلقة) | تُفشل البوابة البناء؛ لا يُعاد التفسير |
| هذا الملحق (ه.2–ه.8) | عرض بشري مطابق حرفياً للمخطط + القرارات الدلالية | نفس الحكم |
| `rendergraph.manifest.json` | جرد الحقول (المسار/النوع/الوحدة/الإمكان) — الملحق أ | لا يُضاف حقل في أحدهما دون الآخر |
| الملحق أ §أ.12 | قواعد الرفض العابرة للحقول | تبقى مرجعاً؛ هـ يضيف ما يعجز المخطط عن التعبير عنه فقط |

الملحق هـ **لا يفتح** قراراً محسوماً في أ: نفس الـ ticks، نفس `ppm`/`millibel`، نفس منع أسماء `mlt`، ونفس «المحرك بلا حالة». كل ما يضيفه هو **تحديد النوع والدلالة**، وكل قرار دلالي جديد مسجَّل في §ه.6 ببديله المرفوض.

### ه.2 قواعد نموذج الأنواع (ست قواعد ملزمة)

| # | القاعدة | الصيغة الدقيقة |
| --- | --- | --- |
| R1 | «مطلوب» و«يقبل null» شيئان مستقلان | الحقل مطلوب ما لم يُكتب `?`؛ ويقبل `null` فقط إذا كُتب `\| null`. مثال: `asset_id` **مطلوب** لكنه يقبل `null` (مقطع لون)، و`clips` **اختياري** ويقبل `null` (مسار صوتي) |
| R2 | لا قيم افتراضية | غياب حقل اختياري = «لا ينطبق»، وليس صفراً ولا 100%. المحرك لا يستنتج قيمة |
| R3 | التعدادات مغلقة | أي حرف خارج القائمة = `RG_SCHEMA_INVALID` (لا «أقرب قيمة») |
| R4 | الأعداد صحيحة على الحدود | لا `float` في أي حقل زمني أو نسبة؛ النسب تُنقل كزوج `num/den` أو `ppm` |
| R5 | لا حقول إضافية | `additionalProperties: false` عند كل عقدة؛ أي مفتاح غير معلن = `RG_UNKNOWN_FIELD` |
| R6 | الحدود تُفحص قبل أي عمل | الحدود الرقمية والقوالب (uuid/hex/URI/لون) جزء من العقد، لا «تحقق دفاعي» اختياري |

**الفرق بين `null` والغياب:** `null` يعني «المفهوم غير موجود لهذا العنصر» (مثل `asset_id` لمقطع لون). الغياب يعني «هذا الحقل لا ينطبق على هذا النوع من الكائن» (مثل `clips` على مسار صوتي). كليهما صريح؛ لا ثالث.

### ه.3 الأنواع الأساسية

| النوع | JSON | القيد | الوحدة |
| --- | --- | --- | --- |
| `Ticks` | integer | ≥ 0 (موضع) أو > 0 (مدة) حسب الحقل | 1/1,000,000 ثانية |
| `Ppm` | integer | 0..1,000,000 | جزء من المليون |
| `PpmSigned` | integer | −1,000,000..1,000,000 | جزء من المليون |
| `Millibel` | integer | −60,000..24,000 | mB (0 = بلا تغيير) |
| `QuarterTurns` | integer | 0..3 | ربع دورة باتجاه عقارب الساعة |
| `UuidV7` | string | `^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$` | — |
| `Blake3Hex` | string | `^[0-9a-f]{64}$` | — |
| `FileUri` | string | `^file:///` (مسار مطلق فقط؛ لا `http`، لا نسبي) | — |
| `RgbaHex` | string | `^#[0-9A-Fa-f]{8}$` | — |

### ه.4 التعريف النوعي (IDL معياري)

الكتلة التالية هي الترجمة الحرفية لـ `rendergraph.schema.json`. كل سطر حقل واحد، والمسافة البادئة بمسافتين. `?` = اختياري، و`\| null` = يقبل null. التعليقات (`//`) ليست جزءاً من النوع.

```ts
// Appendix هـ — RenderGraph v1, do not reorder fields for wire compatibility.

type RenderGraph = {
  graph_schema: "shadow.rendergraph/1";
  sequence_id: UuidV7;
  project_revision: integer;          // >= 0, tracking only
  timebase: Timebase;
  profile: Profile;
  range: Range;
  background_rgba: RgbaHex;
  tracks: Track[];                    // <= 32
};

type Timebase = {
  ticks_per_second: 1000000;          // literal, never another value
  fps_num: integer;                   // >= 1
  fps_den: integer;                   // >= 1
  sample_rate: 44100 | 48000 | 96000;
  channels: integer;                  // 1..8
};

type Profile = {
  width: integer;                     // >= 1
  height: integer;                    // >= 1
  pixel_format: "yuv420p" | "yuv422p" | "yuv444p" | "rgba";
  color_space: "bt709" | "bt2020" | "srgb";
  interlaced: false;                  // literal
};

type Range = {
  start_ticks: integer;               // >= 0
  duration_ticks: integer;            // 1 .. 21600000000 (6h)
};

type Track = {
  id: UuidV7;
  kind: "video" | "audio" | "overlay";
  position: integer;                  // >= 0, unique 0..n-1
  name: string;
  enabled: boolean;
  gain_mb?: integer | null;           // -60000..24000, audio only
  pan_ppm?: integer | null;           // -1000000..1000000, audio only
  clips?: VideoClip[] | null;         // video only, <= 2000
  audio_clips?: AudioClip[] | null;   // audio only, <= 2000
  text_layers?: TextLayer[] | null;   // overlay only, <= 200
  transitions?: Transition[] | null;  // video/audio only, <= 2000
};

type VideoClip = {
  id: UuidV7;
  asset_id: UuidV7 | null;
  kind: "video" | "image" | "color" | "adjustment";
  source_uri: FileUri | null;
  source_hash: Blake3Hex | null;
  stream_index: integer;              // >= -1, -1 = engine picks best
  timeline_start_ticks: integer;      // >= 0
  duration_ticks: integer;            // >= 1
  source_in_ticks: integer;           // >= 0
  speed_num: integer;                 // >= 1
  speed_den: integer;                 // >= 1
  opacity_ppm: integer;               // 0..1000000
  enabled: boolean;
  label?: string | null;              // <= 256 chars, diagnostics only
  transform: Transform;
  effects: Effect[];                  // <= 16
};

type Effect = {
  id: UuidV7;
  effect_key: string;                 // ^shadow\.[a-z0-9_.]+$
  enabled: boolean;
  params: Param[];                    // <= 32
};

type Param = {
  name: string;                       // ^[a-z][a-z0-9_]*$
  type: "int" | "ppm" | "color" | "enum" | "string" | "bool";
  value: Variant;
  keyframes: Keyframe[];              // <= 240
};

type Keyframe = {
  at_ticks: integer;                  // >= 0, absolute timeline
  value: Variant;
  easing: "linear" | "ease_in" | "ease_out" | "ease_in_out" | "step";
};

type Variant = integer | boolean | string;

type Transition = {
  id: UuidV7;
  kind: "crossfade" | "dissolve" | "wipe_left" | "wipe_right" | "fade_black";
  at_ticks: integer;                  // >= 0
  duration_ticks: integer;            // >= 1
  from_clip_id: UuidV7;
  to_clip_id: UuidV7;
};

type TextLayer = {
  id: UuidV7;
  raster_uri: FileUri;
  raster_hash: Blake3Hex;
  raster_width: integer;              // >= 1
  raster_height: integer;             // >= 1
  start_ticks: integer;               // >= 0
  duration_ticks: integer;            // >= 1
  opacity_ppm: integer;               // 0..1000000
  transform: Transform;
  animation_in: Animation;
  animation_out: Animation;
};

type Animation = {
  kind: "none" | "fade" | "slide";
  duration_ticks: integer;            // >= 0, 0 when kind = none
};

type AudioClip = {
  id: UuidV7;
  asset_id: UuidV7 | null;            // null = silence
  source_uri: FileUri | null;
  source_hash: Blake3Hex | null;
  stream_index: integer;              // >= -1
  timeline_start_ticks: integer;      // >= 0
  duration_ticks: integer;            // >= 1
  source_in_ticks: integer;           // >= 0
  speed_num: integer;                 // >= 1
  speed_den: integer;                 // >= 1
  gain_mb: integer;                   // -60000..24000
  fade_in_ticks: integer;             // >= 0
  fade_out_ticks: integer;            // >= 0
  enabled: boolean;
};

type Transform = {
  x_px: integer;
  y_px: integer;
  scale_x_ppm: integer;               // >= 1
  scale_y_ppm: integer;               // >= 1
  rotation_quarter_turns: integer;    // 0..3
  anchor: "top_left" | "center";
  crop_left_px: integer;              // >= 0
  crop_right_px: integer;             // >= 0
  crop_top_px: integer;               // >= 0
  crop_bottom_px: integer;            // >= 0
};
```

**تطابق إلزامي:** لكل مسار `graph.*` في المانيفست خاصية في هذا التعريف، ولكل خاصية هنا سطر في الملحق أ. المدقّق يفشل البناء عند أي انحراف في الاسم أو الإلزام أو النوع أو التعداد أو الحد؛ لا يوجد «تحديث بالنية».

### ه.5 متغيّر `ParamV1.value` — الربط بالنوع (إغلاق آخر ثغرة)

`value` و`keyframes[].value` من النوع `Variant`، ومعناه محدد بـ `ParamV1.type` **مع** تعريف المؤثر في §ه.7:

| `ParamV1.type` | JSON المسموح | المصدر الملزم للقيمة | مثال |
| --- | --- | --- | --- |
| `int` | integer | `min`/`max` من سجل المؤثر | `radius_px = 12` |
| `ppm` | integer | `min`/`max` من السجل (قد يكون سالباً) | `amount_ppm = 500000` |
| `color` | string | `#RRGGBBAA` | `#FF8800FF` |
| `enum` | string | `values` من السجل حصراً | — |
| `string` | string | ≤ 1024 بايت UTF-8 | — |
| `bool` | boolean | — | `true` |

قواعد ملزمة إضافية:

1. `value` يُفحص دائماً من حيث النوع حتى لو وُجدت keyframes (يُهمل حسابياً فقط، كما في §أ.6).
2. `keyframes[].value` يُفحص بنفس جدول النوع؛ لا يُسمح بخلط الأنواع داخل نفس الـ param.
3. كل `name` يجب أن يكون معرَّفاً للمؤثر؛ وإلا `RG_UNKNOWN_PARAM` (V-12).
4. قيمة خارج `min`/`max` = `RG_PARAM_DOMAIN` (V-21) وليس `RG_UNKNOWN_PARAM`: الخطأ في المدى لا في الاسم.
5. لا يوجد param «حر» في v1؛ أي حاجة جديدة = إصدار سجل جديد، لا مفتاح إضافي.

### ه.6 القرارات الدلالية المُلزِمة (سبعة، كلٌّ ببديله المرفوض)

#### D-RG-1 — غياب الحقل ليس قيمة افتراضية

**القرار:** الحقل الاختياري إن غاب لا يشارك في التركيب ولا يُستنتج له بديل. `track.gain_mb = null` يعني «بلا معالجة كسب على هذا المسار»؛ وغياب `clips` على مسار صوتي يعني «غير منطبق»، ولا يُفسَّر كقائمة فارغة.
**المرفوض:** اعتبار الغياب = 0 أو = 1e6 (سلوك شائع في أدوات مخططة)؛ يخلق نتائج مختلفة بين محركين لنفس الـ graph، ويناقض R2.

#### D-RG-2 — مرجع التحجيم: الوسائط تُلائم الإطار، والـ raster بوحدته الأصلية

**القرار:** لمقاطع `video/image` (وأيضاً `adjustment` عند وجود مصدر) يكون المرجع هو **احتواء الأصل داخل `profile`** ثم تُطبَّق النسب:

```
cw = src_w - crop_left - crop_right        ch = src_h - crop_top - crop_bottom
fit = min(W / cw, H / ch)                   // احتواء، بلا تكبير قسري
 dw = floor(cw * fit * scale_x_ppm / 1e6 + 0.5)
 dh = floor(ch * fit * scale_y_ppm / 1e6 + 0.5)
```

أما `text_layers` فالمرجع هو أبعاد الـ raster المعلنة، لأن العقد يحملها صراحةً ولأن §4.4 يشتق الـ raster لدقة العرض المقصودة:

```
dw = floor(raster_width  * scale_x_ppm / 1e6 + 0.5)
dh = floor(raster_height * scale_y_ppm / 1e6 + 0.5)
```

ثم الموضع، ثم الدوران حول مركز الصندوق، ثم القصّ على `[0,W)×[0,H)`:

```
left = (anchor == center) ? floor((W - dw)/2 + 0.5) + x_px : x_px
top  = (anchor == center) ? floor((H - dh)/2 + 0.5) + y_px : y_px
```

**لماذا مرجعان:** `1000000` لمقطع 4K في مشروع 1080p يجب أن يعني «يملأ الإطار» (وهو ما يفعله المثال: transform هوية)، بينما `1000000` لـ raster 1200×180 يجب أن يعني «1200×180 بكسل» وإلا استحال وضع lower-third بحجمه الحقيقي. قاعدة واحدة تجعل أحد الاستخدامين مستحيلاً.
**المرفوض:** (أ) «100% = بكسلات المصدر دائماً» — يجعل المثال يقتطع 4K بدل ملاءمته؛ (ب) «100% = احتواء للجميع» — يكبّر الـ rasters ويعطّل التحكم البكسلي في النص؛ (ج) `cover` بدل `contain` — يقصّ صامتاً ويكسر «ما تراه = ما تصدّره».

#### D-RG-3 — نافذة الانتقال: اللقطات الخارجة تُمدّ بذيلها

**القرار:** النافذة `[at_ticks, at_ticks + duration_ticks)`. المقطع `from` يستمر في القراءة من مصدره بعد نهاية ظهوره المعلنة (نفس `speed`)، والمقطع `to` يبدأ من `source_in_ticks` المعلن **عند بداية النافذة**، أي أن أول `duration` من محتواه تُعرض مخلوطة. الألفا خطية: `a(t) = (t − at)/duration`؛ الخارجي `1−a` والداخل `a`، والتركيب `over` على الخلفية.

**شرط قابلية التنفيذ:** يجب أن يغطي مصدر `from` الامتداد:
`source_in_ticks + (duration_ticks + transition.duration_ticks) × speed ≤ مدة المصدر`، وإلا `RG_TRANSITION_NO_HANDLES` (V-19).
**المرفوض:** (أ) نافذة متمركزة `[at − d/2, at + d/2]` — تتطلب pre-roll من المقطع الداخل، والمثال فيه `source_in_ticks = 0` فيصبح غير قابل للتصدير؛ (ب) تجميد آخر إطار — يخالف QG-4 (نفس المشروع ⇒ نفس الإطارات) ويخفي نقص اللقطات؛ (ج) اعتبار الانتقال «تأثيراً بعد التركيب» — يفصل الصوت عن الصورة ويكسر §أ.7.

#### D-RG-4 — منحنيات التسكين (تعريف رياضي، لا مرجع لسلوك محرك)

**القرار:** حيث `u = (t − at₀)/(at₁ − at₀)` مقصوصة على `[0,1]`:

| `easing` | القيمة |
| --- | --- |
| `linear` | `u` |
| `ease_in` | `u²` |
| `ease_out` | `1 − (1 − u)²` |
| `ease_in_out` | `u² × (3 − 2u)` |
| `step` | `0` حتى `at₁` ثم قيمة الـ keyframe التالي |

هذه الصيغ تُطبَّق على **الزمن الحقيقي** بغض النظر عن معدل الإطارات؛ القيمة المستخدمة في الإطار `f` هي القيمة عند `t = frame_to_tick(f)`.
**المرفوض:** (أ) `cubic-bezier(0.42, 0, 0.58, 1)` كـ CSS — يترك التقريب لتنفيذ المحرك ويخالف QG-4؛ (ب) تسكين خطي فقط مع تجاهل الحقل — يجعل الحقل زخرفة ويخالف V-16؛ (ج) منحنيات باسم المزوّد — تسرّب محرك إلى العقد.

#### D-RG-5 — تقييم الـ keyframes

**القرار:**
1. `at_ticks` **مطلق على الـ timeline**، لا نسبي لبداية المقطع (كما في §أ.6).
2. قبل أول keyframe: قيمة أول keyframe؛ بعد آخرها: قيمة آخرها.
3. بين keyframe‑ين: الصيغة في D-RG-4 مع `at₀/at₁` الخاصين بالزوج.
4. إذا كانت `keyframes = []` تُستخدم `value` الثابتة.
5. الترتيب تصاعدي تماماً وداخل `[timeline_start, timeline_start + duration)`؛ وإلا `RG_KEYFRAME_ORDER` (V-13).

**المرفوض:** تقييم نسبي لبداية المقطع (ينكسر عند trim أو نقل المقطع)؛ أو اعتبار `value` نقطة بداية ضمنية عند tick 0 (يجعل النتيجة تعتمد على حقل «مُهمل»).

#### D-RG-6 — سلسلة الكسب، الـ pan، والتلاشي، والخلط

**القرار — الترتيب الملزم:**

```
عينة المصدر → gain_mb للمقطع → fade_in/fade_out → pan_ppm للمسار → gain_mb للمسار → جمع المسارات
```

- الكسب `mB`: `linear = 10^(mb / 2000)`؛ `−3000` تعني ×0.7079 (−3 dB).
- الـ pan قانون قدرة متساوية: `θ = (pan_ppm + 1e6)/2e6 × π/2`، `L = cos θ`، `R = sin θ`. عند 0 يكون كل قناة ×0.7071 (مجموع القدرة ثابت).
- التلاشي **خطي في السعة** على عدد الـ ticks المعلن، لا لوغاريتمي.
- الجمع حسابي بلا تطبيع تلقائي؛ تجاوز النطاق يُقصّ عند الترميز فقط.
- `asset_id = null` في `AudioClip` = صمت، لا «تخطٍّ».

**المرفوض:** (أ) تطبيع تلقائي بعد الجمع — يجعل نتيجة نفس الـ graph تعتمد على عدد المسارات الأخرى وقوتها؛ (ب) pan خطي — انخفاض −6 dB في المركز؛ (ج) تلاشٍ لوغاريتمي — يختلف عن أي مرجع صوتي ويصعّب المطابقة.

#### D-RG-7 — هندسة حركة النص

**القرار:** `fade` يضرب alpha في `[0,1]` خطياً خلال `duration_ticks` (داخل = تصاعدي، خارج = تنازلي) دون تغيير الموضع. `slide` يُزيح الطبقة رأسياً بمقدار `0.02 × profile.height` بكسل (مقربة half-up): الداخل يبدأ أسفل موضعها بـ `2%` من ارتفاع الإطار ويصعد خطياً إلى موضعها، والخارج يهبط بنفس المقدار؛ الـ alpha لا يتغير. يبقى `opacity_ppm` مضروباً في alpha الـ raster في الحالتين.
**المرفوض:** اتجاه/مسافة قابلة للتهيئة — تتطلب حقولاً جديدة في العقد؛ أو `slide` أفقي ضمن واجهة RTL — يقلب المعنى بين اللغتين.

### ه.7 سجل المؤثرات والانتقالات

**قاعدة القدرات:** `hello_request.capabilities.filters` يساوي حرفياً مفاتيح `filters` في `rendergraph.effects.json`، و`capabilities.transitions` يساوي مفاتيح `transitions` التي `capability = true`. أي مؤثر غير معروض = `RG_UNKNOWN_EFFECT` (V-11)؛ وأي `transition.kind` صالح في التعداد لكنه غير معروض = `RG_UNSUPPORTED_TRANSITION` (V-20)، بلا تقريب صامت.

**`shadow.blur.gaussian`** — ينطبق على `video/image`:

| Param | النوع | الوحدة | المدى | متحرك | الدلالة |
| --- | --- | --- | --- | --- | --- |
| `shadow.blur.gaussian.radius_px` | `int` | px | 0..200 | نعم | sigma في بكسلات الإطار الناتج؛ 0 = هوية |
| `shadow.blur.gaussian.amount_ppm` | `ppm` | ppm | 0..1000000 | نعم | `out = (1 − a) × source + a × blurred(source, radius_px)` |

**`shadow.color_balance`** — ينطبق على `video/image`:

| Param | النوع | الوحدة | المدى | متحرك | الدلالة |
| --- | --- | --- | --- | --- | --- |
| `shadow.color_balance.brightness_mb` | `int` | mB | −24000..24000 | نعم | كسب إضاءة إضافي؛ 0 = هوية |
| `shadow.color_balance.contrast_ppm` | `ppm` | ppm | 0..2000000 | نعم | تباين حول 0.5؛ 1000000 = هوية |
| `shadow.color_balance.saturation_ppm` | `ppm` | ppm | 0..2000000 | نعم | مضاعف تشبع؛ 1000000 = هوية |

**الانتقالات:** `crossfade` و`dissolve` معروضان (الألفا في D-RG-3، ويجب أن يعطيا بكسلات متطابقة)؛ `wipe_left` و`wipe_right` و`fade_black` معرّفة في التعداد لكنها **غير معروضة في v1** وتُرفض بـ V-20.

### ه.8 ربط المخطط بأكواد الرفض

أخطاء البنية كلها من فئة واحدة قابلة للتصنيف آلياً، مع `path` و`keyword` في `ipc_error.context`:

| المخالفة | `keyword` | الكود |
| --- | --- | --- |
| حقل مطلوب غائب | `required` | `RG_SCHEMA_INVALID` (V-22) |
| JSON نوع خاطئ (string بدل int، إلخ) | `type` | V-22 |
| `null` في حقل لا يقبل null | `type` | V-22 |
| قيمة خارج `enum` | `enum` | V-22 |
| خرق `pattern` (uuid/hex/URI/لون) | `pattern` | V-22 |
| خرق `minimum`/`maximum`/`maxItems`/`maxLength` | `minimum`/`maximum`/`maxItems`/`maxLength` | V-22 |
| حقل غير معلن | `additionalProperties` | `RG_UNKNOWN_FIELD` (V-16) |
| مؤثر/param غير معروف | — | `RG_UNKNOWN_EFFECT`/`RG_UNKNOWN_PARAM` (V-11/V-12) |
| قيمة param خارج مدى السجل | — | `RG_PARAM_DOMAIN` (V-21) |

**ترتيب المراحل ملزم:** (1) تحقق المخطط حقلاً بحقل، (2) قواعد §أ.12 العابرة للحقول، (3) التحقق من الوسائط والـ hashes. لا يُبدأ التركيب قبل نجاح الثلاثة؛ ولا يُصلح المحرك بنفسه خطأً بنيوياً.

### ه.9 قواعد الرفض الإضافية (تكمل §أ.12)

| # | الكود | الشرط | التصرف |
| --- | --- | --- | --- |
| V-19 | `RG_TRANSITION_NO_HANDLES` | `from` clip بلا ذيل يكفي `transition.duration_ticks` بعد نهاية ظهوره | رفض، لا تجميد ولا تكرار |
| V-20 | `RG_UNSUPPORTED_TRANSITION` | `kind` صالح في التعداد لكنه غير معروض في `capabilities.transitions` | رفض صريح (لا تقريب) |
| V-21 | `RG_PARAM_DOMAIN` | قيمة param خارج `min`/`max`/`values` المعرّفة في السجل | رفض |
| V-22 | `RG_SCHEMA_INVALID` | أي خرق بنيوي للمخطط (ه.8) مع `path` و`keyword` | رفض |

**المرفوض:** كود منفصل لكل كلمة مفتاحية في JSON Schema (سبعة أكواد إضافية) — يربط العقد بتفاصيل مكتبة التحقق ويجعل الإضافة القادمة تغييراً كاسراً؛ الكود الواحد مع `keyword` يعطي نفس الدقة للإصلاح دون ذلك الارتباط.

### ه.10 ما لا يغطيه المخطط (قائمة سلبية)

| غير مغطى | لماذا | أين يُعالَج |
| --- | --- | --- |
| التقاطع بين الحقول (نوع المسار ↔ حقوله، التراكب، الحدود، تناسق الانتقال) | JSON Schema لا يعبّر عنها بوضوح بلا تكرار هش | §أ.12 (V-04..V-18) كمرحلة ثانية إلزامية |
| تفاوض الإصدار والقدرات | يعتمد على `hello` وقت التشغيل لا على الـ graph | §أ.1 و§5.2 |
| `RenderPresetV1` ورسائل preview/render/project/import/AI | خارج كائن الـ graph | §أ.10 والملحق د |
| الناتج البصري للمؤثرات (قيم بكسلات) | المخطط يقيد **المدخلات** فقط؛ الحتمية تُقاس | QG-4 (`framemd5`) |
| أسماء محرك أو خدمات MLT | ممنوعة أصلاً في أي حقل | §أ.15 + فحص التسريب |
| الافتراضات الضمنية | لا توجد؛ R2 يمنعها | هذا الملحق §ه.2 |
| التحقق من وجود الملفات ومطابقة الـ hash | يعتمد على نظام الملفات وقت التشغيل | V-09/V-15 |

---

*نهاية الوثيقة — `SS-ARCH-001` v1.0*
