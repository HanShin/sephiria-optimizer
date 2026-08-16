# Sephiria Optimizer

Sephiria 플레이 중 인벤토리를 화면으로 읽고, 아티팩트 증폭 초과가 없는 범위에서 석판과 아티팩트의 추천 위치를 계산하는 macOS·Windows 보조 앱입니다.

게임 프로세스, 세이브 파일, 게임 입력은 건드리지 않습니다. 현재 데이터 기준은 Sephiria 1.0.27이며, 공개된 [세피리아 위키 시뮬레이터](https://www.sephiria.wiki/simulator)의 아티팩트 목록과 석판 규칙을 사용합니다.

## Windows 실행

완성된 Windows x64 패키지는 `windows/dist/Sephiria-Optimizer-Windows-<VERSION>-x64.zip`입니다. 현재 버전은 루트의 `VERSION` 파일에서 확인할 수 있습니다.

1. ZIP을 원하는 폴더에 완전히 압축 해제합니다.
2. `Sephiria Optimizer.exe`를 실행합니다. 서명되지 않은 개인용 앱이라 Windows SmartScreen이 표시되면 `추가 정보` → `실행`을 선택합니다.
3. Sephiria는 창 모드 또는 테두리 없는 창 모드로 실행하고 인벤토리를 엽니다. 최소화된 창과 전체화면 독점 모드는 캡처할 수 없습니다.
4. `F8`을 누릅니다. 다른 프로그램이 F8을 사용 중이면 `Alt+Ctrl+I`를 사용합니다.
5. 첫 실행에서는 첫 슬롯의 왼쪽 위 바깥선부터 마지막 슬롯의 오른쪽 아래 바깥선까지 슬롯 격자만 드래그합니다.
6. 주황색 `확인 필요` 칸은 캡처 아이콘과 후보 그림을 비교해 한 번만 직접 지정합니다. 직접 확정한 화면 샘플만 로컬에 저장되며 다음 캡처부터 자동으로 같은 아이템을 찾습니다.
7. 아래의 추천 배치대로 게임에서 직접 옮깁니다.

새 캡처를 하면 직전 인식 결과는 버리고 새 화면으로 다시 계산합니다. 잘못 확정한 아이템이 반복되면 `잘못된 인식 학습 초기화`를 실행하세요.

## macOS 실행

완성된 앱은 `dist/Sephiria Optimizer.app`입니다. 처음 실행할 때 macOS가 화면 기록 권한을 요청하면 허용한 뒤 앱을 다시 실행하세요.

1. Sephiria에서 인벤토리를 엽니다.
2. 인벤토리 슬롯 수는 화면에서 자동 감지됩니다. 잘못 잡힌 경우에만 왼쪽에서 수정합니다.
3. `F8`을 누릅니다. Mac의 기능 키 설정 때문에 작동하지 않으면 `⌥⌘I`를 사용합니다.
4. 첫 실행에서는 첫 슬롯의 왼쪽 위 바깥선부터 마지막 슬롯의 오른쪽 아래 바깥선까지 슬롯 격자만 드래그합니다. 갈색 판의 넓은 여백은 포함하지 않습니다.
5. 확실한 아이템만 자동 입력됩니다. `확인 필요` 칸을 클릭하면 방금 캡처한 원본 아이콘과 후보 그림이 크게 표시됩니다. 맞는 아이템을 선택하면 화면 모습이 아이템당 최대 5장까지 로컬에 누적 학습됩니다.
6. 아래의 추천 배치대로 게임에서 직접 옮깁니다.

인식 영역은 정규화 좌표로 저장되므로 같은 화면 모드와 UI 배율에서는 다음부터 F8 한 번으로 캡처·인식·계산합니다.
잘못 선택한 학습 때문에 후보가 계속 꼬이면 왼쪽의 `잘못된 인식 학습 초기화`를 한 번 실행한 뒤 다시 캡처하세요.

## 빌드와 테스트

### macOS

```sh
./scripts/package_app.sh
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/sephiria-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sephiria-swiftpm-module-cache \
swift test --disable-sandbox --cache-path /tmp/sephiria-swiftpm-cache
```

### Windows

Node.js 22 이상이 설치된 환경에서 실행합니다. macOS에서도 네이티브 의존성이 없는 Windows x64 ZIP을 교차 빌드할 수 있습니다.

```sh
cd windows
npm ci
npm test
npm run dist:win
```

Windows판 아이템 그림과 확인된 화면 샘플은 패키지에 포함되므로 실행할 때 인터넷 연결이 필요하지 않습니다. 사용자 확인 학습과 보정 좌표는 Electron의 사용자 데이터 폴더에만 저장됩니다.

## 버전과 릴리스

버전은 루트의 `VERSION` 한 곳에서 관리합니다. `Info.plist`, `windows/package.json`, `windows/package-lock.json`은 다음 명령으로 함께 갱신됩니다.

```sh
node scripts/version.mjs check
node scripts/version.mjs resolve patch
```

릴리스는 변경 사항을 모두 커밋한 깨끗한 `main` 브랜치에서 실행합니다.

```sh
./scripts/release.sh patch --push
```

`patch` 대신 `minor`, `major`, 또는 `0.3.0`처럼 정확한 버전을 입력할 수 있습니다. 스크립트는 버전을 동기화하고 Windows와 macOS 테스트를 통과한 뒤 릴리스 커밋과 `v<버전>` 태그를 만듭니다. `--push`를 지정하면 GitHub에 태그를 올리고, GitHub Actions가 운영체제별 배포 파일과 SHA-256 체크섬을 Release에 게시합니다.

버전 규칙은 다음과 같습니다.

- 패치(`0.2.1`): 인식·화면·최적화 오류 수정
- 마이너(`0.3.0`): 새 기능 또는 지원 아이템 추가
- 메이저(`1.0.0`): 설정·학습 데이터 호환성이 깨지는 큰 변경

다음 버전에 포함할 사용자 대상 변경 사항은 `CHANGELOG.md`의 `Unreleased`에 기록합니다. 빌드 결과물과 `node_modules`는 Git에 커밋하지 않고 GitHub Release에서만 배포합니다.

## 데이터 갱신

게임 버전이 올라가 위키 데이터가 변경되면 다음처럼 아티팩트 목록을 다시 만들 수 있습니다.

```sh
curl -fsSL https://www.sephiria.wiki/simulator -o /tmp/sephiria-simulator.html
python3 scripts/sync_catalog.py /tmp/sephiria-simulator.html Sources/SephiriaOptimizerApp/Resources/artifacts.json
```

석판 수치 규칙은 `TabletEffectEngine.swift`에 로컬로 구현되어 있으므로 게임 업데이트 때 별도 대조가 필요합니다.
