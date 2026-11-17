# Shadow Studio — Documentation

فهرس وثائق المشروع. **الأساس المعماري الحالي هو v2.0** (وكيل مستقل، بلا Backend، تنفيذ محلي)؛ وv1.0 يبقى مرجعاً لعقد المحرك المتحقَّق منه. لا تُعدَّل وثيقة معمارية دون رفع رقم إصدارها.

## Architecture

| الوثيقة | الحالة | الملاحظات |
| --- | --- | --- |
| [Software Architecture Specification v2.0](architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md) | ✅ **Approved baseline** | إحدى عشرة وحدة، Agent Runtime بـ Dart، عامل وسائط منفصل، صلاحيات وموافقات، تخزين محلي، عقود داخلية، ميزانيات، تتبّع، وخريطة انتقال من v1 |
| [Software Architecture Specification v1.0](architecture/SOFTWARE-ARCHITECTURE-SPEC-v1.0.md) | 🟡 **Superseded** (مرجع عقد) | تفكيك الأنظمة القديم (Python/FastAPI) متقاعد؛ **الملحق أ** و**الملحق هـ** يظلان المصدر المعياري لـ `RenderGraph` |
| [MVP UI/UX Design Specification v1.0](design/MVP-UI-UX-SPEC-v1.0.md) | ✅ Design baseline (D1) | نظام تصميم مُتحقَّق التباين، App shell، Timeline، Preview، Export، حالات، RTL، إمكانية وصول |

### Contracts (machine-validated)

عقد المحرك هو الحد الوحيد الذي يعبر إلى native، لذلك يبقى مخططاً حقلياً مغلقاً حتى مع تغيّر بقية المعمارية:

| الملف | الدور |
| --- | --- |
| [rendergraph.schema.json](architecture/contracts/rendergraph.schema.json) | **المخطط النوعي المعياري** (JSON Schema 2020-12، كائنات مغلقة): كل حقل، نوعه، تعداده، حدوده، وإلزامه — الملحق هـ |
| [rendergraph.effects.json](architecture/contracts/rendergraph.effects.json) | سجل المؤثرات والانتقالات: أنواع وأمدية ومعاني معاملات v1، وقاعدة القدرات |
| [rendergraph.manifest.json](architecture/contracts/rendergraph.manifest.json) | جرد الحقول: المسار + النوع + الوحدة + الإمكان (331 حقلاً + 7 أنواع مشتركة) |
| [rendergraph.example.json](architecture/contracts/rendergraph.example.json) | مثال كامل لكل الأشكال (graph + preview/render + project/import/asset + jobs + AI + error) — أشكال v1 غير الشبكية تُقرأ كمرجع، وأشكال HTTP/IPC متقاعدة في v2 |
| [validate_contract.py](architecture/contracts/validate_contract.py) | الأنواع، الحقول غير المعلنة، القيود الدلالية، تطابق الملاحق مع المانيفست، والـ DDL |
| [validate_schema.py](architecture/contracts/validate_schema.py) | مطابقة المخطط ↔ المانيفست ↔ المثال ↔ IDL الملحق هـ ↔ سجل المؤثرات |
| [validate_v2.py](architecture/contracts/validate_v2.py) | v2.0: الوحدات واتجاه الاعتماد، أهداف الجودة الرقمية، قرارات V2-D وبدائلها، الأدوات والأكواد، خريطة الانتقال، ومنع أي ادعاء خادم |

```bash
python3 docs/architecture/contracts/validate_contract.py   # عقد المحرك + مرحلة schema
python3 docs/architecture/contracts/validate_schema.py      # المخطط الحقلي وحده
python3 docs/architecture/contracts/validate_v2.py          # اتساق وثيقة v2.0
```

## Design

| الملف | الدور |
| --- | --- |
| [verify_design_spec.py](design/verify_design_spec.py) | يفحص: ترتيب الأقسام، معرّفات الحالات، صحة كل مرجع `§`، وجود كل كود خطأ وأمر تحرير وpreset في المعمارية، وإعادة حساب **كل** نسبة تباين مُعلنة |

```bash
python3 docs/design/verify_design_spec.py   # exit 0 = الوثيقة متسقة مع نفسها ومع المعمارية
```

## Security

| الملف | الدور |
| --- | --- |
| [PERMISSIONS.md](security/PERMISSIONS.md) | **حدود الأمان المعيارية**: تصنيف المخاطر (LOW/MEDIUM/HIGH)، فرض الصلاحيات fail-closed، الموافقات الأحادية المرتبطة بـ hash، حماية المسارات وsymlink، حارس الأوامر الخارجية، مخزن مفاتيح API المشفّر، وسجل تدقيق مُسلسَل بالـ hash، مع خريطة اختبارات ونطاق المخاطر المتبقية |

```bash
(cd packages/permissions && dart test)          # محرك الصلاحيات + اختبارات عدائية
(cd packages/tool_system && dart test)          # تكامل المنفّذ + الحارس
(cd packages/provider_gateway && dart test)     # تخزين مفاتيح مشفّر + egress
```

## البناء والتحقق (CI)

| الملف | الدور |
| --- | --- |
| [tool/ci/verify.sh](../tool/ci/verify.sh) | بوابة محلية مكافئة لـ CI: تنسيق (الملفات المتغيرة) ← `dart analyze` (workspace + كل الحزم غير الـworkspace) ← اختبارات `contracts`/`context_engine`/`agent_runtime`/`tool_system`/`provider_gateway`/`permissions`/`local_storage`/`editing_core`/`media_core`/`render_pipeline` ← `flutter test` لسطح المكتب |
| [tool/ci/check_format.sh](../tool/ci/check_format.sh) | يفحص تنسيق ملفات Dart المتغيرة فقط مقابل base ref (لا يعيد تنسيق المستودع كله) |
| [tool/ci/validate_docs.py](../tool/ci/validate_docs.py) | يتحقق من وجود وثائق العقد، الحد الأدنى للمحتوى، علامات §11/§13 وD1–D3 في v2.0، و`pubspec` كل وحدة |
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | التنسيق، التحليل، مصفوفة اختبارات، اختبارات سطح المكتب، بناء Linux release، ورفع المصنوعات/الأدلة عند الفشل |

```bash
./tool/ci/verify.sh
```

## Render pipeline

| الملف | الدور |
| --- | --- |
| [render_pipeline](../packages/render_pipeline) | قارئ `shadow.rendergraph/1` بمخطط مغلق (`RenderGraphDoc` + رموز رفض `RG_*`)، **مخطِّط FFmpeg** (`RenderPlanner`: base، trim/scale/pad، `xfade`/`concat`، طبقات نص、`amix`)، **طابور عرض** (`RenderQueue`: تقدّم، إلغاء تعاوني، مخرج ذرّي `.part` → rename)، و`ProcessRenderBackend` («التقدّم» من `-progress pipe:1`) |

```bash
(cd packages/render_pipeline && dart test)   # 28 اختباراً: المخطط + الخطة + الطابور + presets
```

## القادم (بالترتيب، انظر §18 من v2.0)

| # | المُخرَج | الحالة |
| --- | --- | --- |
| D1 | Repository & File Structure + CI matrix | ✅ CI: [ci.yml](../.github/workflows/ci.yml) (format/analyze/matrix tests/docs/desktop build + artifacts) و[verify.sh](../tool/ci/verify.sh) — كل البوابات خضراء محلياً |
| D2 | Data Model & Migrations | ✅ مخطط v2 + مستودعات SQLite + هجرة forward-only + `transaction`/`integrityCheck` في [data-model.md](data-model.md)، واختبارات `storage_data_model_test.dart` |
| D3 | Internal Contracts (Dart) + Tool JSON Schemas | ✅ عقود Agent/Tool/Checkpoint + مدقق مخططات مغلق + إلغاء/مهلة + أخطاء منظّمة في [contracts.md](contracts.md)، مع اختبارات `contracts`/`agent_runtime`/`tool_system` |
| D4 | Media Worker PoC | 🟡 سبايك FFmpeg يستهلك الـ RenderGraph وينتج MP4 مُتحقَّقاً منه (pixels + audio + QG-4) في [tools/media-spike](../tools/media-spike/README.md)؛ العامل الأصلي (C++/MLT) لم يبدأ |
| D5 | Editing Core Skeleton | ✅ أوامر (clip/track/transition/text/audio/effects) + `DocumentInvariants` + `resolveGraph` (يُصدر رستر النص فقط) في [editing_core](../packages/editing_core) مع 59 اختباراً |
| D6 | Provider Gateway + Adapteran | ✅ [provider_gateway](../packages/provider_gateway): Anthropic/OpenAI adapters، transport HTTP، store مفاتيح مشفّر |
| D7 | Tool Registry + أول 3 أدوات | ✅ [tool_system](../packages/tool_system): `timeline_edit_tool` + `core_editing_adapter` + أدوات الوسائط، بصلاحيات مُنفَّذة |
| D8 | Permission Engine + Approval UX | ✅ [permissions](../packages/permissions): تصنيف مخاطر، موافقة أحادية مربوطة بـhash، حارس مسارات/أوامر، secret store، تدقيق متسلسل |
| D9 | Recovery + Agent Checkpoints | ✅ [local_storage](../packages/local_storage) (SQLite + هجرة forward-only) و checkpoints/Recovery في `agent_runtime` |
| D10 | Integration & Test Plan | ✅ [verify.sh](../tool/ci/verify.sh) + [ci.yml](../.github/workflows/ci.yml) يغطيان كل الحزم أعلاه |
| UX-P1 | Prototype عالي الدقة (timeline + export) | 🟡 نموذج تفاعلي يعمل في المتصفح (RTL + محور LTR، ripple، pre-flight، تقدّم/فشل/استئناف) في [prototype/ux-p1](../prototype/ux-p1/README.md)؛ جاهز لـ T1–T5 |
| UX-P2 | اختبار 5 مستخدمين | ⏳ لم يبدأ |
| UX-P3 | حزمة strings عربية + l10n keys | ⏳ لم يبدأ |
