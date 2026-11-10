# imitation_game

Godot 4, 2D, GDScript 기반의 모작 공방 시뮬레이션 게임이다. 이 저장소는 Leader 세션이 지휘하는 다중 컨텍스트 체계로 개발한다.

## 역할 파일을 먼저 읽는다

이 저장소에서 일하는 모든 세션은 역할이 하나씩 있다. 작업을 시작하기 전에, 그리고 Leader가 "역할 파일이 바뀌었다"고 알릴 때마다 자기 역할 파일을 읽는다. 역할 파일의 규칙은 대화로 받은 이전 지시보다 우선한다.

| 역할 | 역할 파일 |
| --- | --- |
| Leader | `docs/roles/leader.md` |
| planner | `docs/roles/planner.md` |
| worker-01, worker-02 | `docs/roles/worker.md` |
| designer | `docs/roles/designer.md` |
| reviewer | `docs/roles/reviewer.md` |

- 자기 역할은 세션을 시작할 때 받은 지시에 적혀 있다. 지시에 역할이 없으면 Leader다.
- 역할 파일은 메인 체크아웃 `C:\Users\aica_\Desktop\Project\test\docs\roles\`에 있다. worktree에서 일하는 세션은 자기 worktree에 이 폴더가 없으면 위 절대 경로에서 읽는다.
- 모든 역할은 `docs/roles/common.md`의 공통 규칙도 따른다.
- 역할 파일과 `docs/leader/`는 Leader만 고친다.

## 문서 위치

| 경로 | 내용 | 작성 |
| --- | --- | --- |
| `docs/roles/` | 역할별 규칙 | Leader |
| `docs/leader/` | 설계안, 작업지시서 | Leader |
| `docs/planning/` | 게임 기획서 | planner |
| `docs/design/` | 디자인 명세 | designer |
| `design/` | 시안, 에셋, 디자인 토큰 | designer |
