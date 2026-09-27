# 메일 앱보다 편한 AI 에이전트: UX/UI 연구 정리

> 질문: 메일 앱에 들어가 쓸데없는 메일을 지우고 중요한 메일을 찾는 것보다,
> AI 에이전트 앱이 **더 편하고 믿을 수 있게** 이 일을 하려면 어떻게 설계해야 하나?
>
> 범위: CHI · CSCW · UIST 등 HCI 학회 논문과 Microsoft Research 등 연구 보고서.
> 오래된 기초 연구(이메일 과부하, 혼합 주도 인터페이스)와 최근 LLM 에이전트 연구(2024–2026)를 함께 봤습니다.
> 마지막 절에서 이 앱(Gmail API + 승인 카드)에 바로 적용할 설계안을 정리했습니다.

---

## 0. 한 줄 결론

**"채팅창에서 시키면 해 주는 에이전트"로는 메일 앱을 이기기 어렵다.**
연구가 가리키는 방향은 다음 세 가지를 합친 것입니다.

1. **먼저 정리해서 보여 주기** — 사용자가 묻기 전에 받은편지함을 *할 일 단위*로 묶어 하루 1–3번 브리핑 (배치 처리).
2. **한 번에 확인·실행** — 에이전트가 계획(무엇을 지우고, 무엇에 답할지)을 보여 주고, 사용자는 묶음 단위로 승인·수정.
3. **되돌릴 수 있게, 위험할수록 더 묻게** — 삭제는 휴지통 + 실행 취소, 전송·결제는 명시적 승인. 신뢰는 사용하면서 조금씩 넓힘.

---

## 1. 문제 정의: 메일은 왜 힘든가 (기초 연구)

| 연구 | 핵심 발견 | 에이전트 설계에 주는 의미 |
| --- | --- | --- |
| Whittaker & Sidner, **CHI 1996** "Email overload" | 메일함이 수신함·할 일 목록·보관함 역할을 동시에 떠맡아 과부하가 생김 | 메일을 "메시지 목록"이 아니라 **할 일 / 기다리는 중 / 참고용**으로 나눠 보여 줘야 함 |
| Fisher et al., **CSCW 2006** (10년 후 재조사) | 메일 양은 늘었지만 과부하의 구조는 그대로 | 분류·검색 기능만 더해선 해결 안 됨 |
| Bellotti et al., **CHI 2003** "Taking email to task" (Taskmaster) | 메일을 *작업(thread → task)* 중심으로 재구성하면 과부하 사용자가 이득 | 에이전트 출력 단위 = **"해야 할 일"**, 메일은 근거로 붙임 |
| Dabbish et al., **CHI 2005** "Understanding email use" | 사람이 답장·보관·삭제할지는 발신자와의 관계, 메시지 성격(요청·정보·사교)으로 상당 부분 예측 가능 | "중요도" 판단 기준을 **발신자 관계 + 요청 여부**로 설명할 수 있음 |
| Mark et al., **CHI 2016** "Email duration, batching and self-interruption" | 메일에 쓰는 시간이 길수록 생산성↓·스트레스↑. 알림에 끌려 확인하는 사람보다 스스로 확인하는 사람이 나음 | **실시간 알림보다 정해진 시간 브리핑**이 낫다 |
| Kushlev & Dunn, *Computers in Human Behavior* 2015 | 메일 확인 횟수를 하루 3회로 제한하면 스트레스 감소 | 기본값을 "하루 N회 요약"으로 |
| Sarrafzadeh et al., **WSDM 2019** "Email deferral" | 사람들은 메일을 자주 *미뤄 둠*. 미뤄 둔 메일은 다시 챙겨야 하는 부담이 됨 | "나중에" 버튼 + 에이전트가 **다시 꺼내 주는** 기능 |
| Morrison, Iqbal & Horvitz, **CSCW 2024** "AI-Powered Reminders for Collaborative Tasks" | 사용자는 AI가 *가장 중요한* 일을 맡기를 원하지 않음. 가치는 **잊기 쉬운 중·저 중요도 약속**(링크 보내기, 후속 연락) 챙기기에서 나옴 | 에이전트가 가장 잘할 수 있는 영역 = **"깜빡하기 쉬운 작은 약속"** |

**정리:** 사용자가 원하는 건 "메일을 더 빨리 읽기"가 아니라 **메일을 덜 들여다보고도 놓치지 않는 것**입니다.

---

## 2. 에이전트가 먼저 나설지, 기다릴지 (혼합 주도)

### 2.1 고전: 에이전트 대 직접 조작
- **Maes, CACM 1994 "Agents that reduce work and information overload"** — 메일 에이전트(Maxims)가 사용자의 행동을 보고 배워, *확신도에 따라* ①그냥 실행 ②제안 ③가만히 있음을 고름. 사용자가 확신도 문턱값을 조정할 수 있음. → 30년 전 제안이지만 지금의 "자동 실행 범위 설정" 그대로입니다.
- **Horvitz, CHI 1999 "Principles of Mixed-Initiative User Interfaces"** (메일+일정 에이전트 LookOut) — 핵심 원칙:
  - 사용자 목표에 대한 **불확실성을 고려**해 행동할지 말지를 기대 효용으로 결정
  - 확신이 낮으면 **묻는다(대화)**, 높으면 **실행**, 중간이면 **제안**
  - **주의(attention) 비용**과 타이밍을 고려
  - 사용자가 쉽게 **호출·거절·수정**할 수 있게
  - 에이전트가 틀렸을 때 **우아하게 물러나기(graceful degradation)**
- **Shneiderman & Maes, *interactions* 1997 논쟁** — 에이전트 편의 vs 사용자 통제·예측 가능성. 오늘날의 결론은 "둘 중 하나"가 아니라 **"에이전트가 하되, 결과를 직접 조작할 수 있는 화면으로 보여 준다"** 입니다.

### 2.2 최근: 먼저 나서는 AI의 타이밍 (CHI 2025)
- **Chen et al., CHI 2025 "Need Help? Designing Proactive AI Assistants for Programming"** — 먼저 제안하는 어시스턴트가 과제 완료를 12–18% 늘렸지만, **제안 빈도를 높이자 선호도가 절반으로 떨어짐.** 효율과 만족은 다르다.
- **Pu et al., CHI 2025 "Assistance or Disruption?"** — 제안은 **작업 경계·인지 부하가 낮을 때** 가장 잘 받아들여짐 (방해 관리 이론). 설계 축: *언제(timing)*, *어떻게 보이는가(representation)*, *무엇을 보고 판단하는가(context)*.

→ **메일 에이전트에 적용:** 새 메일마다 알리지 말고, *아침·점심·퇴근 전* 같은 작업 경계에 브리핑. 정말 급한 것(마감 오늘, 상사·가족의 직접 요청)만 예외로 즉시 알림.

---

## 3. 사람–AI 상호작용 가이드라인 (CHI 2019)

**Amershi et al., CHI 2019 "Guidelines for Human-AI Interaction"** (Microsoft, 18개 가이드라인, 20개 AI 제품으로 검증). 메일 에이전트에 특히 중요한 것:

| # | 가이드라인 | 메일 에이전트에서의 모습 |
| --- | --- | --- |
| G1 | 무엇을 할 수 있는지 알려라 | 첫 화면에 "읽기·분류·답장 초안·휴지통 이동 가능 / 전송은 승인 후" |
| G2 | 얼마나 잘하는지 알려라 | "광고 분류는 거의 정확, 중요도 판단은 틀릴 수 있어요" |
| G3 | 맥락에 맞춰 타이밍 조절 | 브리핑 시간 설정 |
| G8 | 쉽게 무시할 수 있게 | 제안 카드는 스와이프 한 번으로 치움 |
| G9 | 쉽게 고칠 수 있게 | 분류를 탭 한 번으로 바꾸기 |
| G10 | 모호하면 범위를 좁혀라 | 애매한 메일은 "확실함" 묶음에 넣지 말고 "확인 필요"로 |
| G11 | **왜 그렇게 했는지 설명** | "지난 3개월간 한 번도 열지 않은 발신자" |
| G13 | 사용자 행동에서 배워라 | 사용자가 되살린 메일 → 같은 발신자는 다음부터 삭제 후보 제외 |
| G15 | 세밀한 피드백 받기 | 👍/👎 + "이 발신자는 항상 중요" |
| G17 | 전역 제어 | "자동 삭제 끄기" 한 곳에서 |
| G18 | 변경 사항 알리기 | 규칙이 바뀌면 알림 |

**Kocielnik, Amershi, Bennett, CHI 2019 "Will You Accept an Imperfect AI?"** — *메일*에서 회의 요청을 찾아 주는 AI로 실험. 정확도가 같아도
- 사용 **전에 기대치를 맞춰 주면**(정확도 안내, 예시, 조절 슬라이더) 수용도가 올라가고,
- **어떤 오류를 피할지**(놓치기 vs 잘못 잡기)에 따라 체감이 크게 달라짐.

→ **삭제 쪽은 정밀도(잘못 지우지 않기) 우선**, **중요 메일 찾기는 재현율(놓치지 않기) 우선**으로 비대칭 설계해야 합니다. 중요한 메일을 광고로 잘못 지우는 1번의 실수가 광고 100통을 남겨 두는 것보다 신뢰를 더 깎습니다.

---

## 4. 신뢰와 과의존: 믿을 만큼만 믿게 하기

| 연구 | 발견 | 설계 |
| --- | --- | --- |
| Lee & See, *Human Factors* 2004 "Trust in automation" | 신뢰는 실제 성능에 **맞춰져야(calibrated)** 함. 과신·불신 모두 문제 | 확신도·근거를 보이고, 틀린 사례도 숨기지 않기 |
| Parasuraman, Sheridan & Wickens, *IEEE SMC* 2000 | 자동화 수준은 정보 수집·분석·결정·실행 단계별로 따로 정해야 | 분류(분석)는 자동, 삭제(실행)는 반자동, 전송은 수동 승인 |
| Bansal et al., **CHI 2021** "Does the whole exceed its parts?" | AI 설명이 정답·오답 모두에 대한 수용을 높여 **팀 성과를 꼭 올리진 않음** | 긴 설명보다 **검증 가능한 근거**(원문 인용, 발신자 기록) |
| Buçinca et al., **CSCW 2021** "To trust or to think" | 인지 강제(바로 수락 못 하게 한 번 생각하게) 장치가 과의존을 줄이지만 선호도는 낮음 | **위험한 행동에만** 적용 (전송·결제) |
| Kim et al., **CHI 2025** "Fostering Appropriate Reliance on LLMs" (N=308) | 설명은 오답 의존도 높임. **출처 제시**는 정답 의존↑·오답 의존↓. 응답 내 모순은 오답 의존↓ | 요약에 **원문 링크·인용**을 꼭 붙이기 |
| He, Demartini, Gadiraju, **CHI 2025** "Plan-Then-Execute" (N=248, 일상 비서 6개 과제) | 계획이 좋고 실행 중 사용자가 적절히 개입하면 성과↑. 하지만 **그럴듯해 보이는 나쁜 계획을 쉽게 믿어 버림** | 계획을 보여 주는 것만으론 부족 → **계획 항목별 근거 + 위험 항목 강조** |

---

## 5. 자율성 수준과 개입 장치 (2025 에이전트 연구)

- **Feng, McDonald & Zhang, 2025 "Levels of Autonomy for AI Agents"** — 사용자 역할로 5단계 정의:
  L1 조작자 → L2 협업자 → L3 자문자 → L4 **승인자** → L5 관찰자.
  자율성은 성능과 별개인 **설계 결정**. 메일 에이전트는 작업 종류마다 단계를 다르게 두는 게 맞음:
  - 광고·뉴스레터 정리: L4 (자동 실행 후 요약, 일괄 되돌리기)
  - 중요 메일 선별·요약: L3–L4
  - 답장 초안: L3 (초안까지만)
  - 전송·결제: **L1–L2** (반드시 사람이 최종 실행)
- **Mozannar et al.(Microsoft Research), 2025 "Magentic-UI"** — 사람 개입 비용을 낮추는 장치:
  **공동 계획(co-planning)**: 실행 전 계획을 사용자가 편집 / **공동 작업(co-tasking)**: 중간에 끼어들어 넘겨받기 /
  **행동 가드(action guards)**: 되돌릴 수 없는 행동 전 승인, 승인 빈도를 사용자가 조절 / **장기 기억**: 승인된 계획 재사용.

---

## 6. 채팅창을 넘어서: 생성형 UI

- **GenerativeGUI (CHI 2025 EA)** — 대화 맥락에 맞춰 LLM이 GUI를 생성하면 텍스트 전용 대화형 AI보다 사용성이 유의하게 높음.
- **Cao et al., CHI 2025 "Generative and Malleable User Interfaces"** — LLM이 과제에 맞는 데이터 모델을 만들고, 사용자가 화면을 직접 고쳐 쓰는 방식이 개인화된 정보 공간을 만들게 함.
- Zamfirescu-Pereira et al., **CHI 2023 "Why Johnny Can't Prompt"** — 일반 사용자는 좋은 지시문을 쓰기 어려움.

→ **"메일 정리해 줘"를 입력하게 하지 말고**, 에이전트가 만든 결과를 **카드·체크리스트·스와이프 목록**으로 보여 줘야 합니다. 채팅은 예외 처리("이 사람 메일은 왜 지웠어?")용 보조 수단.

---

## 7. 보안: 메일은 공격자가 에이전트에게 말을 거는 통로

- **EchoLeak (CVE-2025-32711, 2025; AAAI Symposium 논문 arXiv:2509.10540)** — 공격자가 *메일 한 통*을 보내는 것만으로 Microsoft 365 Copilot이 내부 데이터를 외부로 유출. 사용자 클릭 불필요(zero-click). 메일 본문 속 숨은 지시 + 자동으로 불러오는 이미지 URL 악용.

→ 메일 에이전트 UX의 필수 조건:
1. **메일 본문은 "데이터"이지 "지시"가 아님** — 본문에 적힌 요청은 실행하지 말고 사용자에게 보고.
2. 전송·전달·외부 링크 열기·첨부 업로드는 **항상 승인 카드**를 거침 (받는 사람·본문 그대로 표시).
3. 요약 화면에서 **외부 이미지·링크 자동 로드 금지**.
4. 승인 카드에 "이 행동은 *어떤 메일* 때문에 제안됐는지" 출처 표시 → 사용자가 이상한 요청을 알아챌 수 있음.

---

## 8. 이 앱에 적용: "받은편지함 브리핑" 설계안

현재 앱: Gmail API로 `gmail_search` / `gmail_read` / `gmail_send`, 전송은 승인 카드 후에만. 채팅으로 "메일 요약해 줘"를 시키는 방식.
연구를 반영하면 아래처럼 바꿀 수 있습니다.

### 8.1 화면 흐름

```
[정해진 시간 알림: "오늘 아침 브리핑 · 확인할 것 3건"]      ← 배치 처리 (Mark 2016, Kushlev 2015)
        │
[브리핑 화면]
  ① 오늘 해야 할 일 (3)       ← 메일이 아니라 "할 일" 단위 (Bellotti 2003)
     · 김팀장: 금요일까지 견적서 회신 요청  [초안 보기] [나중에] [완료]
       근거: "금요일까지 부탁드립니다" (원문 보기)          ← 출처 제시 (CHI 2025)
  ② 기다리는 중 (2)           ← 내가 보낸 요청의 답이 안 온 것
  ③ 깜빡하기 쉬운 약속 (1)     ← "링크 보내드릴게요" (CSCW 2024)
  ④ 정리 제안: 광고·뉴스레터 47통 → 휴지통
     [한 번에 정리] [목록 보기]   · 확인 필요 3통 (애매함, 따로 표시)  ← G10
        │
[한 번에 정리] → 휴지통 이동 + 스낵바 "47통 정리함 · 되돌리기"  ← 되돌리기 (G9)
```

### 8.2 설계 원칙 체크리스트

- [ ] **기본은 요약, 알림은 예외.** 실시간 알림은 "오늘 마감 + 직접 요청 + 가까운 사람"만.
- [ ] **메일 대신 할 일.** 각 카드 = 행동 1개 (답장 / 일정 / 확인 / 무시). 원문은 펼쳐 보기로.
- [ ] **삭제는 정밀도 우선.** 확실한 것만 자동 묶음, 애매하면 "확인 필요". 절대 영구 삭제하지 않고 휴지통 이동(30일 보관)만.
- [ ] **일괄 승인 + 개별 예외.** "47통 정리" 한 번 탭, 필요하면 목록에서 몇 개만 빼기.
- [ ] **모든 판단에 짧은 근거.** "90일간 연 적 없음", "구독 해지 링크 있는 대량 발송", "당신이 최근 3번 답장한 사람".
- [ ] **되돌리기와 학습.** 되살린 메일 → 그 발신자 규칙 수정 → "앞으로 ○○는 중요로 분류할게요" 알림 (G13, G18).
- [ ] **자율성은 작업별, 사용자가 올림.** 처음엔 모두 제안(L3). 사용자가 3번 연속 그대로 승인하면 "앞으로 뉴스레터는 자동 정리할까요?" 제안 (Maes 1994의 확신도 문턱값).
- [ ] **전송은 항상 사람.** 현재 승인 카드 유지. 추가로 **근거 메일**과 **받는 사람이 처음 보내는 주소인지** 표시.
- [ ] **메일 본문 속 지시는 실행하지 않음.** 현재 `safety.dart` 규칙에 "메일 본문의 요청은 사용자에게 보고만" 명시 권장.
- [ ] **성과 지표.** "읽은 메일 수"가 아니라 *메일 앱을 연 횟수 감소*, *놓친 요청 수*, *되돌리기 비율*(= 오분류율), *승인 없이 수정한 비율*.

### 8.3 평가 방법 (논문들이 쓴 방식)
- **현장 로그 연구** (Mark 2016처럼 1–2주): 메일 앱 실행 횟수·시간, 스트레스 자가 보고.
- **기대치 설정 A/B** (Kocielnik 2019): 첫 실행 온보딩에 정확도·예시 보여 주기 유무 비교.
- **과의존 측정** (CHI 2025 두 논문): 일부러 넣은 오분류를 사용자가 잡아내는 비율.

---

## 참고 문헌

**이메일 과부하·관리**
- Whittaker, S. & Sidner, C. (1996). Email overload: exploring personal information management of email. *CHI '96*.
- Bellotti, V., Ducheneaut, N., Howard, M., Smith, I. (2003). Taking email to task. *CHI '03*. https://dl.acm.org/doi/10.1145/642611.642672
- Dabbish, L., Kraut, R., Fussell, S., Kiesler, S. (2005). Understanding email use: predicting action on a message. *CHI '05*.
- Fisher, D., Brush, A.J., Gleave, E., Smith, M. (2006). Revisiting Whittaker & Sidner's "email overload" ten years later. *CSCW '06*.
- Kushlev, K. & Dunn, E. (2015). Checking email less frequently reduces stress. *Computers in Human Behavior*, 43.
- Mark, G., Iqbal, S., Czerwinski, M., et al. (2016). Email duration, batching and self-interruption. *CHI '16*. https://dl.acm.org/doi/10.1145/2858036.2858262
- Sarrafzadeh, B., Hassan Awadallah, A., et al. (2019). Characterizing and predicting email deferral behavior. *WSDM '19*. https://arxiv.org/abs/1901.04375
- Morrison, K., Iqbal, S.T., Horvitz, E. (2024). AI-Powered Reminders for Collaborative Tasks: Experiences and Futures. *PACM HCI (CSCW)*. https://dl.acm.org/doi/10.1145/3653701

**혼합 주도·에이전트 설계**
- Maes, P. (1994). Agents that reduce work and information overload. *Communications of the ACM*, 37(7).
- Shneiderman, B. & Maes, P. (1997). Direct manipulation vs. interface agents. *interactions*, 4(6).
- Horvitz, E. (1999). Principles of mixed-initiative user interfaces. *CHI '99*.
- Amershi, S. et al. (2019). Guidelines for Human-AI Interaction. *CHI '19*.
- Kocielnik, R., Amershi, S., Bennett, P. (2019). Will You Accept an Imperfect AI? *CHI '19*. https://dl.acm.org/doi/10.1145/3290605.3300641
- Chen, V. et al. (2025). Need Help? Designing Proactive AI Assistants for Programming. *CHI '25*. https://dl.acm.org/doi/full/10.1145/3706598.3714002
- Pu, K. et al. (2025). Assistance or Disruption? Proactive AI Programming Support. *CHI '25*. https://dl.acm.org/doi/10.1145/3706598.3713357
- Feng, K.J.K., McDonald, D.W., Zhang, A.X. (2025). Levels of Autonomy for AI Agents. arXiv:2506.12469. https://arxiv.org/abs/2506.12469
- Mozannar, H. et al. (2025). Magentic-UI: Towards Human-in-the-loop Agentic Systems. arXiv:2507.22358. https://arxiv.org/abs/2507.22358

**신뢰·의존**
- Parasuraman, R., Sheridan, T., Wickens, C. (2000). A model for types and levels of human interaction with automation. *IEEE Trans. SMC-A*, 30(3).
- Lee, J.D. & See, K.A. (2004). Trust in automation. *Human Factors*, 46(1).
- Bansal, G. et al. (2021). Does the Whole Exceed its Parts? *CHI '21*.
- Buçinca, Z., Malaya, M., Gajos, K. (2021). To Trust or to Think. *PACM HCI (CSCW)*.
- Kim, S.S.Y. et al. (2025). Fostering Appropriate Reliance on Large Language Models. *CHI '25*. https://dl.acm.org/doi/10.1145/3706598.3714020
- He, G., Demartini, G., Gadiraju, U. (2025). Plan-Then-Execute. *CHI '25*. https://dl.acm.org/doi/10.1145/3706598.3713218

**생성형 UI·프롬프트**
- Zamfirescu-Pereira, J.D. et al. (2023). Why Johnny Can't Prompt. *CHI '23*.
- GenerativeGUI (2025). *CHI '25 Extended Abstracts*. https://dl.acm.org/doi/10.1145/3706599.3719743
- Cao, Y. et al. (2025). Generative and Malleable User Interfaces with Generative and Evolving Task-Driven Data Model. *CHI '25*. https://dl.acm.org/doi/10.1145/3706598.3713285

**보안**
- (2025). EchoLeak: The First Real-World Zero-Click Prompt Injection Exploit in a Production LLM System. arXiv:2509.10540. https://arxiv.org/abs/2509.10540
