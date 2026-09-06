# WhyNot 시스템 설정 & 데이터베이스(DB) 배포 가이드

본 문서는 **WhyNot 프로젝트**를 실제 운용 환경(Production/Supabase)에 구축하거나 이전할 때, **개발자가 직접 수행(적용)해야 하는 DB SQL 마이그레이션, 환경변수, 배포 설정**을 완벽하게 정리한 마스터 가이드입니다.

---

## 🗄️ 1. 데이터베이스(Supabase SQL) 마이그레이션 적용 순서

WhyNot 프로젝트는 Supabase (PostgreSQL) 기반으로 구동됩니다. Supabase 대시보드의 **SQL Editor**에서 아래 SQL 파일들을 **순서대로 실행**해야 데이터베이스 테이블, 뷰, RLS 보안 정책 및 함수가 올바르게 입혀집니다.

> 💡 **참고**: 모든 SQL 마이그레이션 파일은 프로젝트 루트 디렉토리에 위치해 있으며 바탕화면 백업 압축 파일(`whynot_project_code_backup.zip`)에도 포함되어 있습니다.

### 📋 마이그레이션 실행 순서

| 순서 | 파일명 | 설명 및 필수 조치 |
|:---:|:---|:---|
| **1** | `supabase_master_migration_full.sql` | **[마스터 베이스라인]** 초기 스키마, 기본 테이블(`rooms`, `ideas`, `evaluations`, `users` 등) 및 함수/RLS 정책 통합 생성 |
| **2** | `supabase_auth_hotfix_forward.sql` | **[인증 핫픽스]** 사용자 세션 쿠키 인증 및 비밀번호 단방향 해시(bcrypt) 처리를 위한 DB 프로시저 적용 |
| **3** | `supabase_migration_invites.sql` | **[초대 & 정원]** 방 개별 초대 및 조직 정원 관리용 테이블(`room_invites`, `org_memberships` 등) 생성 |
| **4** | `supabase_migration_phase2_persona_forward.sql` | **[2차 페르소나]** 페르소나 중심 익명 의견 제안 및 동시 공개 스냅샷용 DB 구조 확장 |
| **5** | `supabase_migration_phase3_decision_engine_forward.sql` | **[3차 의사결정 엔진]** 빠른 결정 모드, 80% 기준 합의 투표, 재검토 이력(`evaluation_rounds`), AI 근거 리포트 저장용 테이블/컬럼 추가 |

---

## 🛠️ 2. 필수 환경 변수 (`.env`) 설정

서버(`server.ts`) 및 Express BFF 레이어 구동을 위해 프로젝트 루트에 `.env` 파일을 생성하고 다음 값들을 입력해야 합니다.

```env
# 1. 서버 포트 설정
PORT=3000

# 2. Supabase 연동 정보 (Supabase Project Settings > API 에서 확인)
SUPABASE_URL=https://<YOUR_SUPABASE_PROJECT_ID>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1Ni... # (주의: Service Role Key 필수, Client Key 사용 금지)

# 3. 비밀번호 해싱 및 쿠키 암호화용 Salt/Secret
COOKIE_SECRET=whynot_super_secret_cookie_key_2026

# 4. (선택) Open AI / LLM API 키 - AI 근거 리포트 요약 기능 사용 시
OPENAI_API_KEY=sk-...
```

---

## 🗄️ 3. ERD & DB 주요 테이블 구조 요약

| 테이블명 (Table) | 핵심 기능 및 주요 컬럼 (Columns) | 비고 |
|:---|:---|:---|
| `rooms` | 회의실/의사결정 룸 정보<br>(`id`, `title`, `decision_mode`, `target_winner_count`, `engine_version`, `status`) | `decision_mode`: `FAST` (빠른 결정) / `STRUCTURED` (심층 결정) |
| `ideas` | 제안된 선택지/후보 아이디어<br>(`id`, `room_id`, `author_id`, `title`, `content`, `is_revealed`) | 작성 마감 전까지 `is_revealed=false`로 익명 유지 |
| `evaluation_rounds` | 회차별 재검토 이력 및 투표 상태<br>(`id`, `room_id`, `round_number`, `tie_status`, `tie_winner_ids`) | 동률 발생 시 `TIE_PENDING` 관리 |
| `ai_reports` | AI 근거 리포트 및 프롬프트 고정 기록<br>(`id`, `room_id`, `round_id`, `report_json`, `model_version`) | 우승자 선정 사유, 미확인 가정, 우려사항 기록 |
| `room_invites` | 회원/비회원 전용 방 초대 및 정원 제어<br>(`id`, `room_id`, `invite_code`, `email`, `role`, `status`) | 정원 초과 시 입장 차단 |

---

## 🚀 4. 서버 및 앱 실행 가이드

1. **의존성 패키지 설치**
   ```bash
   npm install
   ```
2. **개발 모드 실행 (BFF Express 서버 + Vite HMR)**
   ```bash
   npm run dev
   ```
3. **프로덕션 빌드 & 실행**
   ```bash
   npm run build
   node dist/server.js
   ```

---

## ⚠️ 5. 주의사항 & 운영 체크리스트

1. **Supabase Service Role Key 보안**: `.env`에 설정하는 `SUPABASE_SERVICE_ROLE_KEY`는 RLS 정책을 우회할 수 있는 강력한 키이므로 클라이언트(브라우저) 코드에 노출되어서는 안 됩니다. (Express BFF `server.ts` 내부에서만 참조 사용)
2. **비밀번호 저장 보안**: 모든 비밀번호는 `pgcrypto`를 통해 `crypt()` 함수로 단방향 암호화 처리됩니다.
3. **기존 데이터 하위 호환성**: `engine_version = 3` 컬럼을 통해 과거 생성된 결정 룸의 데이터 구조가 깨지지 않도록 하위 호환성이 보장됩니다.
