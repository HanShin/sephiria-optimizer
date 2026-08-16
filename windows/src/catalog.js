const fs = require('node:fs');
const path = require('node:path');

const tabletRows = [
  ['chivalry', '기사도', true], ['dry', '건조', false], ['approximation', '근사', true],
  ['advent', '도래', true], ['linear', '선의', false], ['sight', '시선', true],
  ['handshake', '악수', true], ['fate', '운명', false], ['wit', '재치', true],
  ['exploitation', '착취', true], ['unity', '화합', true], ['cheer', '환호', false],
  ['hope', '희망', true], ['nurture', '양육', true], ['joke', '장난', true],
  ['compete', '경쟁', true], ['beating', '고동', true], ['home_town', '고양', true],
  ['past', '과거', true], ['future', '미래', true], ['distribution', '분배', false],
  ['triceps', '삼두', false], ['harvesting', '수확', true], ['binary_star', '쌍성', true],
  ['yearning', '열망', false], ['agglutination', '응집', true], ['entrance', '입구', false],
  ['load', '적재', true], ['transition', '전이', true], ['advance', '전진', true],
  ['justice', '정의', false], ['preparation', '준비', true], ['exit', '출구', false],
  ['tide', '파도', true], ['dedication', '헌정', false], ['honor', '명예', true],
  ['rally', '집결', true], ['development', '발전', true], ['base', '기반', false],
  ['warrant', '권능', true], ['disconnection', '단절', false], ['concurrency', '동시성', false],
  ['vow', '맹세', true], ['rebellion', '반항', true], ['connection', '이음', true],
  ['junction', '접합', true], ['last_stand', '배수진', false], ['flag', '깃발', false],
  ['defender', '방어수', false], ['shade', '차양', false], ['wedge', '쐐기', true],
  ['thorn', '가시', false], ['boundary', '경계', false], ['sheen', '광휘', true],
  ['miracle', '기적', false], ['daydream', '백일몽', true], ['compression', '압축', true],
  ['certitude', '확신', true], ['hospitality', '환대', false], ['courage', '용기', true],
  ['peace', '평화', true]
];

function templateKey(itemId) {
  return itemId.replaceAll(':', '_').replaceAll('/', '_');
}

function loadCatalog(resourceDirectory) {
  const artifacts = JSON.parse(fs.readFileSync(path.join(resourceDirectory, 'artifacts.json'), 'utf8'));
  const artifactItems = artifacts.map((artifact) => ({
    id: `artifact:${artifact.value}`,
    kind: 'artifact',
    name: artifact.label_kor,
    englishName: artifact.label_eng,
    capacity: Number(artifact.level || 0),
    isRotatable: false,
    templateKey: `artifact_${artifact.value}`
  }));
  const tabletItems = tabletRows.map(([id, name, isRotatable]) => ({
    id: `tablet:${id}`,
    tabletId: id,
    kind: 'tablet',
    name,
    englishName: id,
    capacity: 0,
    isRotatable,
    templateKey: `tablet_${id}`
  }));
  return [...artifactItems, ...tabletItems];
}

module.exports = { loadCatalog, templateKey, tabletRows };
