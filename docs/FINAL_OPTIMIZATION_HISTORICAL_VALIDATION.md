# 이전 최적화 증거의 historical 검사

2026-11-09의 이전 최적화 패키지와 측정은 이후 R09/R11/R14 등의 소스 변경에 앞선 기록이다. 현재 소스와 현재 앱이 이전 hash와 달라진 사실을 과거 증거의 손상으로 판단하지 않도록 [검사기](../scripts/check-final-optimization-validation.py)에 `--historical`을 추가했다. 기본 모드는 계속 현재 소스·현재 배포 앱과의 일치를 요구한다.

실행 결과:

```sh
python3 scripts/check-final-optimization-validation.py --historical --require-complete
# PASS
```

[결과 JSON](validation/final-optimization-2026-11-09/final-evidence-check-historical.json)은 기존 `final-evidence-check.json`과 별도 파일이다. 기존 raw, source hash, 원본 완료 receipt, ZIP은 수정하지 않았다. 이 변경은 검사기와 문서에 한정되며 앱 source나 배포물을 다시 만들지 않는다.

검사 대상은 다음과 같다.

- `packaged-source-manifest.json`의 116개 파일을 `packaged-source-archive`에서 hash 검사한다. manifest 자체도 원본 완료 receipt의 SHA와 대조한다.
- kernel report의 측정 당시 83개 source를 `paired-final/source-archive`에서 검사한다. 기존 검사기의 Core·renderer hot-path 부분은 packaged source와도 동일해야 한다. 나중 App lifecycle 변경을 이전 측정 소스와 동일한 것으로 확대하지 않는다.
- 보존 release ZIP의 SHA, ZIP 내부 binary와 `main-ready.json`의 SHA, ZIP 내부 MCP와 packaged source를 대조한다. ZIP을 임시 디렉터리로 `ditto` 추출해 실제 `codesign --verify --deep --strict`를 실행하고 제거한다. 앱 실행은 없다.
- 기존 kernel 150개, render 2,500 frame, native navigation/resize 각 버전 200개, visibility/Space/occlusion, 25회 lifetime, packaged test/MCP/architecture oracle 검사는 유지한다. 보존 로그·상태를 재검사하며 새 runtime 측정을 생성하지 않는다.
- 완료 수 116과 pending 없음은 **원본 완료 receipt의 내용**이다. historical 모드에서는 현재 TODO와 progress를 평가하지 않는다. 따라서 `--require-complete`는 원본 receipt가 완결된 상태인지 검사할 뿐, 이후 추가된 작업의 완료를 주장하지 않는다. 원본 receipt에는 개별 116개 체크 상태 전체가 없어 현재 TODO의 과거 상태를 독립 재구성하는 검증도 아니다.

보존 package SHA는 `3f4e09f3932e0caaec0691b1ebdb2bfbc96aa6a7e65da721ca9872b956c8a94e`, source manifest SHA는 `88ce5bc2a4f3cdef3544a8a5bce1177e76289ecdb988018f7c02fd3756f57a2c`, 원본 완료 receipt SHA는 `694af895011d1b4aa55558bc33b6ec5263f6a5ca8be5b6dc453530bd021ca59e`다. 새 결과에는 실행한 checker 자체의 SHA도 기록한다.

이 PASS는 보존 증거의 hash·oracle·signature 일관성 결과다. 현재 변경된 앱의 correctness/performance, Windows 동적 동등성, Intel 실기기 동작, 장기 heap 안정성을 새로 검증한 결과로 사용하지 않는다. 기존 x86_64 CLI 결과는 Apple Silicon의 Rosetta 실행이다.
