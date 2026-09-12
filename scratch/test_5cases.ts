import dotenv from 'dotenv';
dotenv.config();

const POTENS_API_URL = 'https://ai.potens.ai/api/chat';
const apiKey = process.env.POTENS_API_KEY || process.env.GEMINI_API_KEY || '';

const cases = [
  {
    name: '1. 명백한 오탈자',
    title: '인스타그램 채널 활용',
    description: '인스타그램에 유미당 공식 채널을 생성해하고, 일대일 통해 에피소드들을 애니메이션화해서 영상들을 업로드하여 유미당 서비스를 알린다.'
  },
  {
    name: '2. 맞춤법은 맞지만 어색한 문장',
    title: '회의 결과 확인',
    description: '사용자가 회의를 진행을 하면서 결과를 확인하는 것이 가능하게 한다.'
  },
  {
    name: '3. 이미 자연스러운 문장',
    title: '평가 기준 검토',
    description: '팀원들이 동일한 평가 기준으로 아이디어를 검토할 수 있도록 한다.'
  },
  {
    name: '4. 수치가 포함된 문장',
    title: '아이디어 등록 제한',
    description: '참여자는 최대 3개의 아이디어를 등록할 수 있다.'
  },
  {
    name: '5. 기능 설명이 포함된 문장',
    title: '동률 처리 룰렛',
    description: '최종 투표에서 동률이 발생하면 모든 참여자의 동의를 받은 뒤 룰렛을 진행한다.'
  }
];

async function run() {
  for (const c of cases) {
    const prompt = `
당신은 팀 의사결정 서비스의 전문 한국어 문장 교정 및 표현 보완 도우미입니다.
작성자의 핵심 아이디어, 사실, 기능, 수치는 정확히 보존하되, 비문과 어색한 어미/조사는 자연스러운 문장 구조로 재작성하여 완벽한 한국어 문장으로 교정하세요.

[필수 교정 및 문법 검수 규칙]
1. 원문 입력에 비문이나 오탈자가 있더라도 그 어색한 구조나 단어를 절대 그대로 보존하려고 하지 마세요.
2. 아래 항목이 단 하나라도 남아있다면 절대 그대로 반환하지 말고 반드시 자연스럽게 수정하세요:
   - 중복/어색한 어미 (예: "생성해하고" -> "생성하고")
   - 조사 누락 및 잘못된 조사 (예: "일대일 통해" -> "1:1 소통을 통해" 또는 "일대일로 소통하며")
   - 비문, 잘못된 어휘 활용, 중복 표현
3. 최종 결과를 반환하기 직전에 스스로 다음 질문으로 검수하세요:
   "한국어 화자가 읽었을 때 어색한 조사, 중복 어미, 비문(예: '생성해하고', '일대일 통해' 등)이 단 하나라도 남아있는가?" -> 만약 남아있다면 완전히 매끄러운 한국어 문장으로 바로잡은 뒤 반환하세요.
4. 원문의 핵심 의미, 사실, 기능, 수치만 유지하고, 문장 구조·조사·어미는 완전히 자연스러운 한국어가 되도록 자유롭게 재구성해도 좋습니다.
5. 원문에 없는 새로운 기능, 수치, 장점, 추측 사실은 임의로 추가하지 마세요.
6. 아이디어의 우수성이나 실현 가능성을 평가/비판하지 마세요.
7. 작성자가 스스로 아이디어를 구체화할 수 있는 검토 질문을 최대 3개 작성하세요.

[원문 제목]
${c.title}

[원문 내용]
${c.description}

반드시 아래 형식의 유효한 JSON만 출력하세요. 다른 설명이나 마크다운 코드블록 없이 순수 JSON만 응답하세요.
{
  "revisedDescription": "문법 검수를 거쳐 매끄럽고 완벽하게 교정된 최종 문장",
  "reviewQuestions": ["검토 질문 1", "검토 질문 2", "검토 질문 3"]
}
`;

    try {
      const res = await fetch(POTENS_API_URL, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ prompt, model: 'gpt-4o' })
      });
      const data = await res.json();
      let raw = data.result?.response || data.response || data.text || JSON.stringify(data);
      let parsed;
      try {
        let cleaned = raw.replace(/```json|```/g, '').trim();
        parsed = JSON.parse(cleaned);
        if (parsed.result?.response) {
          parsed = JSON.parse(parsed.result.response.replace(/```json|```/g, '').trim());
        }
      } catch (e) {}

      console.log(`=== ${c.name} ===`);
      console.log('INPUT:', c.description);
      console.log('OUTPUT:', parsed?.revisedDescription || raw);
      console.log('');
    } catch (err) {
      console.log(`=== ${c.name} ERROR ===`, err instanceof Error ? err.message : err);
    }
  }
}

run();
