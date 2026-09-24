# 한국 주요 모바일 서비스 TOP100 — 브라우저 자동화 지원 현황

기준일: 2026-09-24 · 서비스 109개 · 지원 81 · 일부 9 · 앱 전용 10 · 보안상 제외 9

> 이 표는 `server/app/services.json` 에서 생성됩니다. 앱과 서버가 같은 파일을 쓰며, 에이전트는 `service_info` 도구로 여기의 URL·팁을 참고합니다.

## 선정 방법

- 모바일인덱스 **2026년 상반기 대한민국 모바일 앱 TOP100**의 공개 요약(상위 3: YouTube·카카오톡·네이버, ChatGPT 17위 등)과,
  업종별 MAU 순위(커머스·OTT·음악·여행·금융·배달 등, 와이즈앱·모바일인덱스 보도)를 합쳐 **분류별로 재구성**했습니다.
- 원문 TOP100 표 전체는 이 개발 환경에서 열람할 수 없어, **정확한 순위 번호 대신 분류별 목록**으로 정리했습니다. 게임은 제외했습니다.
- **지원 기준**
  - ✅ 지원: 모바일 웹에서 로그인·검색·핵심 기능(주문·예약·작성 등)이 가능
  - 🟡 일부: 웹은 조회 위주이고 핵심 기능은 앱 전용이거나, 본인인증이 필요해 사용자가 직접 처리
  - ❌ 앱 전용: 웹 버전이 없거나 기능이 기기·위치에 묶임 (예: 배달의민족, 카카오톡, 카카오 T)
  - ⛔ 보안상 제외: 송금·은행·본인인증 — 사용자 자산 보호를 위해 에이전트가 다루지 않음
- 결제·주문 확정·전송·예약 확정은 서비스와 관계없이 **항상 사용자 승인 후**에만 진행됩니다 (코드에서 강제).
- URL 은 공식 도메인 기준이며, 실제 사이트 개편에 따라 달라질 수 있습니다. 검색 URL 은 확인된 경우에만 넣었습니다.

## 서비스 목록

| 분류 | 서비스 | 지원 | 시작 주소 | 비고 |
| --- | --- | --- | --- | --- |
| 동영상 | YouTube | ✅ 지원 | https://m.youtube.com/ | 재생목록 정리, 구독 채널 확인, 영상 검색 |
| 메신저 | 카카오톡 | ❌ 앱 전용 |  | 채팅은 앱(PC 앱) 전용이고 웹 버전이 없음 |
| 메신저 | 디스코드 | ✅ 지원 | https://discord.com/app |  |
| 포털 | 네이버 | ✅ 지원 | https://m.naver.com/ | 검색, 뉴스, 날씨. 네이버 계정 하나로 쇼핑·지도·예약·메일·카페가 모두 로그인됨 |
| 포털 | Google 검색 | ✅ 지원 | https://www.google.com/ |  |
| 브라우저 | Chrome | ❌ 앱 전용 |  | 브라우저 자체(에이전트가 이미 크롬을 사용) |
| 쇼핑 | 쿠팡 | ✅ 지원 | https://m.coupang.com/ | 장바구니: https://cart.coupang.com/cartView.pang . 가격·단위가격·로켓배송·리뷰를 비교. 결제 비밀번호(쿠페이)는 사용자에게 넘김 |
| 쇼핑 | 11번가 | ✅ 지원 | https://m.11st.co.kr/ |  |
| 쇼핑 | 네이버플러스 스토어 (네이버쇼핑) | ✅ 지원 | https://shopping.naver.com/ | 여러 쇼핑몰 가격 비교에 유용 |
| 쇼핑 | G마켓 | ✅ 지원 | https://www.gmarket.co.kr/ |  |
| 쇼핑 | 옥션 | ✅ 지원 | https://www.auction.co.kr/ |  |
| 쇼핑 | 다이소몰 | ✅ 지원 | https://www.daisomall.co.kr/ |  |
| 쇼핑 | 롯데ON | ✅ 지원 | https://www.lotteon.com/ |  |
| SNS | 인스타그램 | ✅ 지원 | https://www.instagram.com/ | 피드·DM·프로필 확인 가능. 게시·DM 전송은 승인 후 |
| SNS | X (트위터) | ✅ 지원 | https://x.com/ |  |
| SNS | 페이스북 | ✅ 지원 | https://m.facebook.com/ |  |
| SNS | 스레드 | ✅ 지원 | https://www.threads.com/ |  |
| 지도·예약 | 네이버 지도·플레이스·예약 | ✅ 지원 | https://map.naver.com/ | 장소 검색, 길찾기, 플레이스 페이지의 '예약' 버튼으로 식당·미용실·병원 예약. 예약 확정은 승인 후 |
| 지도 | 카카오맵 | ✅ 지원 | https://map.kakao.com/ | 장소 검색·길찾기 |
| 내비게이션 | 티맵 | ❌ 앱 전용 |  | 내비게이션은 앱 전용 |
| 중고거래·동네 | 당근 | 🟡 일부 | https://www.daangn.com/ | 웹에서는 매물 검색·열람만 가능하고 채팅·거래는 앱 전용 |
| 배달 | 배달의민족 | ❌ 앱 전용 |  | 주문 가능한 웹이 없음 |
| 배달 | 쿠팡이츠 | ❌ 앱 전용 |  | 주문은 앱 전용 |
| 배달 | 요기요 | 🟡 일부 | https://www.yogiyo.co.kr/ | 웹 주문 기능이 제한적일 수 있음 |
| AI | ChatGPT | ✅ 지원 | https://chatgpt.com/ |  |
| 금융 | 토스 | ⛔ 보안상 제외 |  | 송금·금융 서비스는 보안상 에이전트 자동화에서 제외 |
| 금융 | 카카오뱅크 | ⛔ 보안상 제외 |  | 은행 앱은 보안상 제외 |
| 금융 | KB스타뱅킹 | ⛔ 보안상 제외 |  | 은행 앱은 보안상 제외 |
| 금융 | 신한 SOL뱅크 | ⛔ 보안상 제외 |  | 은행 앱은 보안상 제외 |
| 금융 | 우리WON뱅킹 | ⛔ 보안상 제외 |  | 은행 앱은 보안상 제외 |
| 금융 | 하나원큐 | ⛔ 보안상 제외 |  | 은행 앱은 보안상 제외 |
| 결제 | 카카오페이 | ⛔ 보안상 제외 |  | 결제·송금은 보안상 제외 |
| 결제 | 네이버페이 (주문·배송 조회) | 🟡 일부 | https://pay.naver.com/ |  |
| 결제 | 삼성 월렛 | ❌ 앱 전용 |  | 기기 결제·신분증 기능으로 앱 전용 |
| 웹툰 | 네이버웹툰 | ✅ 지원 | https://m.comic.naver.com/ | 관심 웹툰 새 회차 확인 |
| 웹툰 | 카카오웹툰 | ✅ 지원 | https://webtoon.kakao.com/ |  |
| 웹툰·웹소설 | 카카오페이지 | ✅ 지원 | https://page.kakao.com/ |  |
| OTT | 넷플릭스 | ✅ 지원 | https://www.netflix.com/ | 찜 목록·신작 확인(재생은 사용자가) |
| OTT | 쿠팡플레이 | ✅ 지원 | https://www.coupangplay.com/ |  |
| OTT | 티빙 | ✅ 지원 | https://www.tving.com/ |  |
| OTT | 웨이브 | ✅ 지원 | https://www.wavve.com/ |  |
| OTT | 디즈니+ | ✅ 지원 | https://www.disneyplus.com/ |  |
| 음악 | YouTube Music | ✅ 지원 | https://music.youtube.com/ | 재생목록 만들기·곡 추가 |
| 음악 | 멜론 | ✅ 지원 | https://www.melon.com/ | 플레이리스트 관리, 차트 확인 |
| 음악 | 지니뮤직 | ✅ 지원 | https://www.genie.co.kr/ |  |
| 음악 | Spotify | ✅ 지원 | https://open.spotify.com/ |  |
| SNS·커뮤니티 | 네이버 밴드 | ✅ 지원 | https://band.us/ | 공지·일정 확인, 글쓰기는 승인 후 |
| 커뮤니티 | 네이버 카페 | ✅ 지원 | https://m.cafe.naver.com/ | 가입한 카페 새 글 확인, 글쓰기는 승인 후 |
| 커뮤니티 | 에브리타임 | ✅ 지원 | https://everytime.kr/ |  |
| 블로그 | 네이버 블로그 | ✅ 지원 | https://m.blog.naver.com/ |  |
| 숏폼 | 틱톡 | ✅ 지원 | https://www.tiktok.com/ |  |
| 라이브 방송 | 치지직 | ✅ 지원 | https://chzzk.naver.com/ |  |
| 라이브 방송 | SOOP (숲) | ✅ 지원 | https://www.sooplive.co.kr/ |  |
| 패션 | 에이블리 | 🟡 일부 | https://m.a-bly.com/ | 웹 기능이 앱보다 제한적 |
| 패션 | 무신사 | ✅ 지원 | https://www.musinsa.com/ |  |
| 패션 | 지그재그 | 🟡 일부 | https://zigzag.kr/ | 웹 기능이 앱보다 제한적 |
| 뷰티 | 올리브영 | ✅ 지원 | https://www.oliveyoung.co.kr/ |  |
| 해외직구 | 알리익스프레스 | ✅ 지원 | https://ko.aliexpress.com/ |  |
| 해외직구 | 테무 | ✅ 지원 | https://www.temu.com/ |  |
| 카페 | 스타벅스 | 🟡 일부 | https://www.starbucks.co.kr/ | 사이렌오더(주문)는 앱 전용, 웹은 카드·쿠폰 조회 위주 |
| 중고거래 | 번개장터 | ✅ 지원 | https://m.bunjang.co.kr/ | 구매·채팅은 승인 후 |
| 장보기 | 컬리 | ✅ 지원 | https://www.kurly.com/ |  |
| 편의점 | 우리동네GS | ❌ 앱 전용 |  | 픽업·배달 주문은 앱 전용 |
| 인테리어 | 오늘의집 | ✅ 지원 | https://ohou.se/ |  |
| 쇼핑·장보기 | SSG.COM (이마트몰) | ✅ 지원 | https://www.ssg.com/ |  |
| 여행 | 트립닷컴 | ✅ 지원 | https://kr.trip.com/ |  |
| 여행·숙박 | 야놀자 (NOL) | ✅ 지원 | https://www.yanolja.com/ |  |
| 여행·숙박 | 여기어때 | ✅ 지원 | https://www.yeogi.com/ |  |
| 여행·숙박 | 아고다 | ✅ 지원 | https://www.agoda.com/ko-kr/ |  |
| 여행·숙박 | 에어비앤비 | ✅ 지원 | https://www.airbnb.co.kr/ |  |
| 항공 | 스카이스캐너 | ✅ 지원 | https://www.skyscanner.co.kr/ |  |
| 항공 | 네이버 항공권 | ✅ 지원 | https://flight.naver.com/ |  |
| 항공 | 대한항공 | ✅ 지원 | https://www.koreanair.com/ |  |
| 항공 | 아시아나항공 | ✅ 지원 | https://flyasiana.com/ |  |
| 기차 | 코레일 (코레일톡) | ✅ 지원 | https://www.korail.com/ | 승차권 조회·예매. 반복 조회로 좌석을 노리는 매크로 예매는 금지. 결제는 승인 후 |
| 기차 | SRT | ✅ 지원 | https://etk.srail.kr/ | 승차권 조회·예매. 매크로 예매 금지. 결제는 승인 후 |
| 버스 | 고속버스 (티머니GO/KOBUS) | ✅ 지원 | https://www.kobus.co.kr/ |  |
| 택시 | 카카오 T | ❌ 앱 전용 |  | 택시 호출은 위치·앱 전용 |
| 카셰어링 | 쏘카 | ❌ 앱 전용 |  | 차량 이용은 앱 전용 |
| 영화 | CGV | ✅ 지원 | https://www.cgv.co.kr/ | 상영시간 조회·예매. 결제는 승인 후 |
| 영화 | 메가박스 | ✅ 지원 | https://www.megabox.co.kr/ |  |
| 영화 | 롯데시네마 | ✅ 지원 | https://www.lottecinema.co.kr/ |  |
| 공연·티켓 | NOL 티켓 (인터파크 티켓) | ✅ 지원 | https://tickets.interpark.com/ | 공연 정보·예매. 대기열·매크로 우회는 하지 않음 |
| 식당 예약 | 캐치테이블 | ✅ 지원 | https://app.catchtable.co.kr/ |  |
| 도서·티켓 | 예스24 | ✅ 지원 | https://www.yes24.com/ |  |
| 도서 | 교보문고 | ✅ 지원 | https://www.kyobobook.co.kr/ |  |
| 도서 | 알라딘 | ✅ 지원 | https://www.aladin.co.kr/ |  |
| 전자책 | 밀리의 서재 | ✅ 지원 | https://www.millie.co.kr/ |  |
| 전자책 | 리디 | ✅ 지원 | https://ridibooks.com/ |  |
| 메일 | Gmail | ✅ 지원 | https://mail.google.com/ | '이 폰' 모드에서는 Gmail API(말투 학습 포함)로 처리됨. 전송은 승인 후 |
| 메일 | 네이버 메일 | ✅ 지원 | https://mail.naver.com/ | 메일 확인·요약, 전송은 승인 후 |
| 포털·메일 | 다음·다음 메일 | ✅ 지원 | https://m.daum.net/ | 메일: https://mail.daum.net/ |
| 일정 | Google 캘린더 | ✅ 지원 | https://calendar.google.com/ | 일정 확인·등록 |
| 일정 | 네이버 캘린더 | ✅ 지원 | https://calendar.naver.com/ |  |
| 파일 | Google 드라이브 | ✅ 지원 | https://drive.google.com/ |  |
| 부동산 | 네이버 부동산 | ✅ 지원 | https://land.naver.com/ |  |
| 부동산 | 직방 | ✅ 지원 | https://www.zigbang.com/ |  |
| 부동산 | 다방 | ✅ 지원 | https://www.dabangapp.com/ |  |
| 부동산 | 호갱노노 | ✅ 지원 | https://hogangnono.com/ |  |
| 채용 | 사람인 | ✅ 지원 | https://www.saramin.co.kr/ | 지원서 제출은 승인 후 |
| 채용 | 잡코리아 | ✅ 지원 | https://www.jobkorea.co.kr/ | 지원서 제출은 승인 후 |
| 아르바이트 | 알바몬 | ✅ 지원 | https://www.albamon.com/ |  |
| 아르바이트 | 알바천국 | ✅ 지원 | https://www.alba.co.kr/ |  |
| 공공 | 정부24 | 🟡 일부 | https://www.gov.kr/ | 본인인증(간편인증·공동인증서)은 사용자가 직접 |
| 공공 | 홈택스 | 🟡 일부 | https://www.hometax.go.kr/ | 본인인증·신고 제출은 사용자가 직접 |
| 공공 | 국민건강보험 | 🟡 일부 | https://www.nhis.or.kr/ | 본인인증 필요, 조회 위주 |
| 공공 | 모바일 신분증 | ⛔ 보안상 제외 |  | 신분증은 보안상 제외 |
| 병원 예약 | 똑닥 | ❌ 앱 전용 |  | 접수·예약은 앱 전용 |
| 본인인증 | PASS | ⛔ 보안상 제외 |  | 본인인증 앱은 보안상 제외 |

## 출처

- [2026년 상반기 대한민국 모바일 앱 TOP100 — 모바일인덱스(IGAWorks)](https://www.igaworksblog.com/post/2026-h1-mobileapp-top100) · [모비인사이드](https://brunch.co.kr/@mobiinside/7524)
- [쿠팡, 2026년 1분기 커머스 앱 MAU·사용시간·재방문율 3관왕 — 플래텀](https://platum.kr/archives/285313)
- [쿠팡 다음은 알리·테무…한국 쇼핑앱 순위 — 한국경제](https://www.hankyung.com/article/202609232466g)
- [2026년 한국인이 가장 많이 사용한 SNS 앱 — 와이즈앱](https://www.wiseapp.co.kr/insight/detail/997)
- [8월 여행 앱 사용자, 트립닷컴·NOL — 플래텀](https://platum.kr/archives/294999)
- [넷플릭스 4월 MAU…쿠팡플레이·티빙 — 아이뉴스24](https://www.inews24.com/view/1965500)
- [쿠팡플레이, 티빙 제치고 국내 OTT 2위 — 서울경제TV](https://www.sentv.co.kr/article/view/sentv202608030205)
- [토스, 은행·뱅킹 앱 사용자 수 1위 — 플래텀](https://platum.kr/archives/253233)
- [2026 배달앱 총정리 — 배달핏](https://baedalfit.com/blog/delivery-app-review-2026/)
- [한국인이 가장 많이 쓰는 모빌리티 앱은 '지도' — 플래텀](https://platum.kr/archives/267614)
- [결제 서비스 트렌드 리포트 2026 — 오픈서베이](https://blog.opensurvey.co.kr/trendreport/payment-2026/)
