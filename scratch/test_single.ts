import dotenv from 'dotenv';
dotenv.config();

const POTENS_API_URL = 'https://ai.potens.ai/api/chat';
const apiKey = process.env.POTENS_API_KEY || process.env.GEMINI_API_KEY || '';

const title = '회의 결과 확인';
const description = '사용자가 회의를 진행을 하면서 결과를 확인하는 것이 가능하게 한다.';

const prompt = `
당신은 팀 의사결정 서비스의 전문 한국어 문장 교정 및 표현 보완 도우미입니다.
작성자의 핵심 아이디어, 사실, 기능, 수치는 정확히 보존하되, 비문과 어색한 어미/조사는 자연스러운 문장 구조로 재작성하여 완벽한 한국어 문장으로 교정하세요.

[필수 교정 및 문법 검수 규칙]
1. 원문 입력에 비문이나 오탈자가 있더라도 그 어색한 구조나 단어를 절대 그대로 보존하려고 하지 마세요.
2. 아래 항목이 단 하나라도 남아있다면 절대 그대로 반환하지 말고 반드시 자연스럽게 수정하세요:
   - 중복/어색한 어미 (예: "생성해하고" -> "생성하고")
   - 조사 누락 및 잘못된 조사 (예: "일대일 통해" -> "1:1 소통을 통해" 또는 "일대일로 소통하며")
   - 비문, 잘못된 어휘 활용, 중복 표현
3. 문장을 자연스럽게 만들기 위해 필요한 조사, 어미, 문장 구조는 자유롭게 수정할 수 있습니다.
4. 그러나 원문에 없는 시간성, 빈도, 속도, 품질, 범위, 효과, 기능, 상태를 새로 추론하거나 임의로 추가하지 마세요.
   - 예시: 원문에 "실시간"이라는 단어나 의미가 없으면 "실시간으로" 등의 수식어를 절대 추가하지 않습니다.
5. 자연스러운 표현을 이유로 정보를 임의로 구체화하거나 부풀리지 말고, 정보량은 원문과 동일하게 유지합니다.
6. 원문에 없는 새로운 기능, 수치, 장점, 추측 사실은 임의로 추가하지 마세요.
7. 아이디어의 우수성이나 실현 가능성을 평가/비판하지 마세요.
8. 작성자가 스스로 아이디어를 구체화할 수 있는 검토 질문을 최대 3개 작성하세요.

[원문 제목]
${title}

[원문 내용]
${description}

반드시 아래 형식의 유효한 JSON만 출력하세요. 다른 설명이나 마크다운 코드블록 없이 순수 JSON만 응답하세요.
{
  "revisedDescription": "문법 검수를 거쳐 매끄럽고 완벽하게 교정된 최종 문장",
  "reviewQuestions": ["검토 질문 1", "검토 질문 2", "검토 질문 3"]
}
`;

async function run() {
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
  console.log('INPUT:', description);
  console.log('REVISED:', parsed?.revisedDescription || raw);
}

run();
