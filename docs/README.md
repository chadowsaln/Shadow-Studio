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

## القادم (بالترتيب، انظر §18 من v2.0)

| # | المُخرَج | الحالة |
| --- | --- | --- |
| D1 | Repository & File Structure + CI matrix | ⏳ لم يبدأ |
| D2 | Data Model & Migrations | ⏳ لم يبدأ |
| D3 | Internal Contracts (Dart) + Tool JSON Schemas | 🟡 الـ RenderGraph كامل ومُتحقَّق؛ عقود الوكيل/الأدوات نصّية فقط |
| D4 | Media Worker PoC | 🟡 سبايك FFmpeg يستهلك الـ RenderGraph وينتج MP4 مُتحقَّقاً منه (pixels + audio + QG-4) في [tools/media-spike](../tools/media-spike/README.md)؛ العامل الأصلي (C++/MLT) لم يبدأ |
| D5 | Editing Core Skeleton | ⏳ لم يبدأ |
| D6 | Provider Gateway + Adapteran | ⏳ لم يبدأ |
| D7 | Tool Registry + أول 3 أدوات | ⏳ لم يبدأ |
| D8 | Permission Engine + Approval UX | ⏳ لم يبدأ |
| D9 | Recovery + Agent Checkpoints | ⏳ لم يبدأ |
| D10 | Integration & Test Plan | ⏳ لم يبدأ |
| UX-P1 | Prototype عالي الدقة (timeline + export) | ⏳ لم يبدأ |
| UX-P2 | اختبار 5 مستخدمين | ⏳ لم يبدأ |
| UX-P3 | حزمة strings عربية + l10n keys | ⏳ لم يبدأ |
