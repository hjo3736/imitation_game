# imitation_game

Godot 4, 2D, GDScript 기반의 모작 공방 시뮬레이션 게임이다. 이 저장소는 Leader 세션이 지휘하는 다중 컨텍스트 체계로 개발한다.

## 자기 역할 폴더를 먼저 읽는다

이 저장소에서 일하는 모든 세션은 역할이 하나씩 있다. 작업을 시작하기 전에, 그리고 Leader가 "역할 파일이 바뀌었다"고 알릴 때마다 다음 둘을 읽는다. 역할 파일의 규칙은 대화로 받은 이전 지시보다 우선한다.

1. `docs/roles/common.md` — 모든 역할의 공통 규칙
2. `docs/roles/<자기 역할>/rules.md` — 자기 역할의 규칙

| 역할 | 폴더 |
| --- | --- |
| Leader | `docs/roles/leader/` |
| planner | `docs/roles/planner/` |
| worker-01 | `docs/roles/worker-01/` |
| worker-02 | `docs/roles/worker-02/` |
| designer | `docs/roles/designer/` |
| reviewer | `docs/roles/reviewer/` |

- 자기 역할은 세션을 시작할 때 받은 지시에 적혀 있다. 지시에 역할이 없으면 Leader다.
- 각 역할 폴더에는 `rules.md`(작업 규칙)와 `outputs/`(그 역할이 만든 문서)가 있다.
- 자기 폴더의 `outputs/`에만 쓴다. 다른 역할의 `rules.md`와 `outputs/`를 읽는 범위는 `docs/roles/common.md` 1절을 따른다.
- `rules.md`와 `common.md`는 Leader만 고친다.
- 역할 폴더의 원본은 메인 체크아웃 `C:\Users\aica_\Desktop\Project\test\docs\roles\`에 있다. worktree에서 일하는 세션은 자기 worktree에 Leader가 알려 준 문서가 없으면 위 절대 경로에서 읽는다.

## 역할별 산출물

| 폴더 | 내용 |
| --- | --- |
| `docs/roles/leader/outputs/` | 설계안, 작업지시서 |
| `docs/roles/planner/outputs/` | 게임 기획서 |
| `docs/roles/worker-01/outputs/`, `docs/roles/worker-02/outputs/` | 작업 보고서 |
| `docs/roles/designer/outputs/` | 디자인 명세, 작업 보고서 |
| `docs/roles/reviewer/outputs/` | 검토 보고서 |

## 프로젝트 폴더

| 경로 | 내용 |
| --- | --- |
| `scenes/<기능>/` | 씬(`.tscn`) |
| `scripts/<기능>/` | 스크립트(`.gd`). 전역 객체의 스크립트도 그 기능의 폴더에 둔다 |
| `themes/` | 테마 리소스 |
| `assets/images/`, `assets/fonts/`, `assets/audio/` | 제품에 들어가는 그림, 글꼴, 소리 |
| `data/` | 게임 수치, 작품 데이터 |
| `tests/<기능>/`, `tests/common/` | 테스트와 확인용 씬. 게임 파일과 섞지 않는다 |
| `design/` | designer의 시안과 원본 (Godot가 읽지 않는다) |
| `docs/` | 문서 (Godot가 읽지 않는다) |

구조의 근거와 규칙은 `docs/roles/leader/outputs/12_설계안.md`에 있다.
