# Windows Codex 팀

업무 한 건을 팀장 → 조사 → 작성 → 독립 검수 → 팀장 취합 순서로 처리하는 파일 기반 자동 실행기입니다. 검수에서 수정을 요청하면 기본 한 번까지 새 버전을 작성하고 다시 검수합니다.

## 준비

- Windows, PowerShell 7, 설치 및 로그인된 Codex CLI가 필요합니다.
- 프로젝트 신뢰 및 Codex Windows 샌드박스 준비를 먼저 완료합니다. 실행기는 권한이나 PowerShell 실행 정책을 변경하지 않습니다.
- Codex 모델 이용 한도가 적용됩니다. 정상 업무는 보통 7회, 수정 한 번은 11회의 CLI 호출을 사용합니다.

## 사용

Codex 데스크톱에서 저장소 루트를 프로젝트로 열고 채팅에 업무를 입력합니다. 루트 AGENTS.md가 접수 assistant에게 요청 파일 생성, 팀 실행, 진행 화면 열기, 상태 안내, 결과 전달을 지시합니다. 앱 전역 메시지 후크나 별도 상주 서비스는 아닙니다.

예: “제공한 메모를 내부 공유용 보고서로 정리하고 검수까지 마쳐줘.”

직접 실행하려면 이 폴더에서 Start-Team.cmd를 열거나 PowerShell 7을 사용합니다.

```powershell
.\Start-Team.ps1 -Task '제공 자료를 보고서로 정리하고 누락을 검수해줘.'
.\Start-Team.ps1 -TaskFile .\examples\support-task.md -Offline
```

`-Offline`은 제공된 로컬 자료만 사용하도록 지시합니다. 기본 수정 한도는 `-MaxRevisions 1`, 단계별 제한 시간은 `-StageTimeoutSeconds 600`입니다. 한 번에 업무 한 건만 처리합니다. 실행 호스트와 PC가 유지되어야 하며, 실행이 끝나면 종료합니다.

## 진행 화면과 결과

- `runs/<task_id>/dashboard.html`: 팀장·조사·작성·검수 상태, 현재 단계, 경과 시간, 완료된 산출물. 단계 전환 및 5초 간격으로 저장하고 실행 중 화면은 3초마다 새로 읽습니다.
- 자동 갱신 일시정지/재개가 가능하며 완료·중단 시 재로드를 멈춥니다. 15초 이상 상태 수신 지연을 표시합니다.
- `runs/<task_id>/status.json`: 원본 실행 상태. 동일 폴더에 단계별 프롬프트와 응답·로그가 남습니다.
- `leader/output/<task_id>-final-r01.md`: 독립 검수를 통과한 최종 결과.

역할은 순차 실행됩니다. 숨겨진 모델 사고, 토큰 사용량, 추정 진행률은 표시하지 않습니다. 화면을 닫는 것은 업무 취소가 아닙니다.

| 상태 | 의미 |
|---|---|
| COMPLETED | 검수 통과 및 로컬 결과 준비 완료 |
| BLOCKED | 자료·접근·판단이 필요하여 중단 |
| NEEDS_APPROVAL | 사람 승인이 필요하여 중단 |
| NEEDS_CHANGES | 자동 수정 한도 이후에도 검수 미통과 |
| FAILED / CANCELLED | 오류·시간 초과·중단 |

## 역할과 권한

각 역할의 AGENTS.md와 `templates/`가 지시·결과·검수 형식을 정의합니다. 팀장은 자기 폴더와 담당자 inbox에 지시를 쓰고, 담당자는 자기 결과와 팀장 inbox에 통지를 씁니다. 팀장은 동일 세션을 재사용하고 조사·작성·검수는 별도 세션으로 호출합니다. 현재 검수도 Codex 기본 모델을 사용하며 다른 회사 모델로 검수하는 기능은 포함하지 않습니다.

`workspace-write`와 `--add-dir`를 사용하지만 AGENTS.md의 역할 범위는 운영체제의 강제 격리가 아닙니다. 상위 workspace가 이미 쓰기 가능하면 `--add-dir`가 이를 차단하지 않습니다. 게시·발송·결제·배포·파괴적 삭제·권한 변경은 사용자 승인에서 멈추도록 지시합니다. 검수 PASS는 외부 행동 승인이 아닙니다.

실제 업무 요청, 역할 inbox/output 결과, 실행 로그는 Git에서 제외합니다. 이 저장소에는 내부 보고서·계정 인증 정보·실제 세션 기록을 포함하지 않습니다.

## 테스트

이 테스트들은 실제 모델을 호출하지 않습니다. 이 폴더에서 실행합니다.

```powershell
pwsh -NoProfile -File .\tests\Test-TeamRunner.ps1
pwsh -NoProfile -File .\tests\Test-TeamDashboard.ps1
node .\tests\Test-TeamDashboardUi.cjs
```

실행기 19개, 대시보드 연동 4개, 화면 스크립트 9개를 검증합니다. Node.js는 UI 테스트에만 필요합니다. `tests/Start-DashboardDemo.ps1`은 가짜 CLI로 진행 화면을 시험하는 예제입니다.