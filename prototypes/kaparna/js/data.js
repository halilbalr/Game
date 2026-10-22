// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall (sätt ut pirater, se dem storma däcket)?
// Date: 2026-10-22
//
// All spelbalans ligger här: trupper, försvar, skepp, ekonomi.
(function () {
  const K = (window.K = window.K || {});

  K.DATA = {
    // +20 % liv och skada per uppgraderingsnivå
    levelScale: 0.2,
    maxLevel: 5,
    // kostnad för att nå nivå N (index = målnivå); multipliceras med truppens upgradeMul
    upgradeCost: [0, 0, 350, 1100, 2800, 6500],

    // Piratfästet styr arméstorlek och antal drycker (besvärjelser)
    harbor: [
      { army: 20, spells: 2, cost: 0 },
      { army: 30, spells: 2, cost: 900 },
      { army: 40, spells: 3, cost: 2600 },
      { army: 50, spells: 3, cost: 5500 },
      { army: 60, spells: 4, cost: 10000 },
    ],

    start: { gold: 250, army: { kampe: 10, skytt: 6 } },

    // unlock = antal olika kapade skepp som krävs
    troops: {
      kampe: {
        name: 'Kämpe', role: 'Närstrid', desc: 'Snabb och modig. Hugger allt i sin väg med sabeln.',
        hp: 75, dmg: 13, atk: 1.0, range: 0.6, speed: 2.0, space: 1, cost: 15,
        target: 'any', unlock: 0, upgradeMul: 1,
      },
      skytt: {
        name: 'Skytt', role: 'Avstånd', desc: 'Skjuter med sin flintlåsmusköt över barrikaderna.',
        hp: 34, dmg: 9, atk: 0.9, range: 3.5, speed: 2.2, space: 1, cost: 30,
        target: 'any', unlock: 0, upgradeMul: 1.2, proj: 'shot',
      },
      bombare: {
        name: 'Bombare', role: 'Spränger barrikader', desc: 'Springer rakt mot närmaste barrikad och spränger hål i den.',
        hp: 30, dmg: 45, wallMul: 10, splash: 1.3, atk: 1, range: 0.6, speed: 3.0, space: 2, cost: 60,
        target: 'wall', unlock: 1, upgradeMul: 1.3,
      },
      bjasse: {
        name: 'Bjässe', role: 'Tank – anfaller försvar', desc: 'Enorm och seg. Bryr sig bara om kanoner och andra försvar.',
        hp: 560, dmg: 30, atk: 2.0, range: 0.75, speed: 1.2, space: 5, cost: 160,
        target: 'defense', unlock: 2, upgradeMul: 1.6,
      },
      plundrare: {
        name: 'Plundrare', role: 'Snabb – jagar byte', desc: 'Blixtsnabb. Går direkt på kistor och containrar och gör dubbel skada på dem.',
        hp: 42, dmg: 13, lootMul: 2, atk: 1.0, range: 0.55, speed: 3.4, space: 1, cost: 25,
        target: 'loot', unlock: 3, upgradeMul: 1.1,
      },
    },

    hero: {
      key: 'kapten', name: 'Kaptenen', role: 'Hjälte', desc: 'Besättningens ledare. Gratis i varje strid. Förmåga: Stridsrop – kallar på fyra kämpar, läker och blir rasande.',
      hp: 1100, dmg: 48, atk: 1.2, range: 0.8, speed: 1.6, target: 'any', upgradeMul: 2,
      ability: { summon: 4, rage: 7, healPct: 0.35 },
    },

    spells: {
      lakning: {
        name: 'Shaah-te', role: 'Läkning', desc: 'Kryddat somaliskt te. Läker dina pirater inom ringen.',
        radius: 3.2, duration: 6, hps: 45, cost: 100, space: 1, unlock: 1, color: '#ffd84a', upgradeMul: 1.4,
      },
      raseri: {
        name: 'Krigstrumma', role: 'Raseri', desc: 'Trumman dånar! Pirater i ringen blir snabbare och slår hårdare.',
        radius: 3.2, duration: 8, dmgMul: 1.6, spdMul: 1.4, cost: 120, space: 1, unlock: 3, color: '#ff4fd8', upgradeMul: 1.4,
      },
    },

    // fiendens vakter (skapas av vaktkur). Skalar med skeppets nivå.
    guard: { hp: 120, dmg: 12, atk: 1.0, range: 0.6, speed: 2.0 },

    // per skeppsnivå (tier): liv ×(1 + hpTier·(tier−1)), skada ×(1 + dmgTier·(tier−1))
    tierScale: { hp: 0.32, dmg: 0.25 },
    wallHp: 300,
    wallPenalty: 6, // vägkostnad för att gå genom en barrikad (i rutor)

    // kind: core | defense | loot | other. loot = andel av skeppets byte (vikt)
    buildings: {
      brygga: { name: 'Kommandobrygga', w: 4, h: 4, hp: 1400, kind: 'core', loot: 2 },
      kanon: { name: 'Kanon', w: 2, h: 2, hp: 420, kind: 'defense', dmg: 26, atk: 0.85, range: 6.0, proj: 'ball' },
      vatten: { name: 'Vattenkanon', w: 2, h: 2, hp: 500, kind: 'defense', dmg: 7, atk: 0.2, range: 3.6, splash: 1.0, slow: 0.5, proj: 'water' },
      utkik: { name: 'Utkikstorn', w: 2, h: 2, hp: 380, kind: 'defense', dmg: 14, atk: 0.6, range: 7.5, proj: 'bullet' },
      morsare: { name: 'Mörsare', w: 2, h: 2, hp: 420, kind: 'defense', dmg: 40, atk: 4.5, range: 9.5, minRange: 3, splash: 1.6, proj: 'shell' },
      vaktkur: { name: 'Vaktkur', w: 2, h: 2, hp: 450, kind: 'defense', trigger: 6, guards: 3 },
      container: { name: 'Container', w: 3, h: 2, hp: 380, kind: 'loot', loot: 1 },
      kista: { name: 'Skattkista', w: 2, h: 2, hp: 620, kind: 'loot', loot: 2.5 },
      fisklada: { name: 'Fisklådor', w: 2, h: 1, hp: 160, kind: 'loot', loot: 0.6 },
      ventil: { name: 'Ventilstation', w: 2, h: 2, hp: 340, kind: 'loot', loot: 1 },
      skorsten: { name: 'Skorsten', w: 2, h: 2, hp: 320, kind: 'other' },
      kran: { name: 'Lastkran', w: 2, h: 2, hp: 300, kind: 'other' },
      livbat: { name: 'Livbåt', w: 2, h: 1, hp: 160, kind: 'other' },
      radar: { name: 'Radarmast', w: 1, h: 1, hp: 240, kind: 'other' },
      helipad: { name: 'Helikopterplatta', w: 3, h: 3, hp: 360, kind: 'other' },
      pool: { name: 'Pool', w: 3, h: 2, hp: 280, kind: 'other' },
    },

    // Skeppen (nivåer). Koordinater i rutor: x längs skeppet (0 = akter), y tvärs.
    // layout: [typ, x, y, {rot: byt bredd/höjd, color, stack}]
    // walls: [x, y, längd, 'h' (längs x) | 'v' (längs y)]
    ships: [
      {
        id: 'tralare', name: 'Olaglig trålare', tier: 1,
        story: 'En utländsk trålare dammsuger våra fiskevatten. Dags att visa vems hav det är!',
        len: 18, beam: 8, bow: 5, loot: 900, income: 18, cap: 500,
        pal: { hull: '#2b6f8f', stripe: '#c8402e', deck: '#b07a48', deckLine: '#7a5230', house: '#eef1f4', accent: '#ff9f1c', flag: ['#f2c14e', '#2b6f8f'] },
        deckType: 'wood',
        layout: [
          ['brygga', 8, 2],
          ['skorsten', 6, 3],
          ['kran', 1, 3],
          ['kista', 4, 2],
          ['fisklada', 1, 1], ['fisklada', 1, 6], ['fisklada', 4, 6],
          ['livbat', 9, 0], ['livbat', 9, 7],
          ['kanon', 13, 3],
          ['vatten', 4, 4],
        ],
        walls: [],
      },
      {
        id: 'lastfartyg', name: 'Lastfartyg', tier: 2,
        story: 'Ett tungt lastat fraktskepp på väg genom Adenviken. Lastrummet är fullt av guld.',
        len: 22, beam: 9, bow: 5, loot: 1600, income: 32, cap: 900,
        pal: { hull: '#3a3f4a', stripe: '#b3261e', deck: '#5f7d4c', deckLine: '#46603a', house: '#f1efe8', accent: '#e8b021', flag: ['#1f6fb2', '#ffffff'] },
        deckType: 'steel',
        decals: [[8, 1, 3, 3], [13, 1, 3, 3], [8, 5, 3, 3]],
        layout: [
          ['brygga', 1, 2],
          ['skorsten', 5, 4],
          ['livbat', 1, 0], ['livbat', 1, 7],
          ['container', 8, 2], ['container', 8, 5, { color: '#2f7fd1' }], ['container', 12, 2, { color: '#3aa357' }],
          ['kista', 13, 5],
          ['kran', 11, 0],
          ['kanon', 17, 3], ['kanon', 5, 6],
          ['vatten', 5, 1],
          ['utkik', 11, 6],
        ],
        walls: [[12, 4, 4, 'h'], [15, 5, 3, 'v'], [13, 7, 2, 'h']],
      },
      {
        id: 'containerfartyg', name: 'Containerfartyg', tier: 3,
        story: 'Ett jättelikt containerfartyg. Vakterna ombord är beväpnade – var försiktig.',
        len: 26, beam: 10, bow: 6, loot: 2600, income: 50, cap: 1500,
        pal: { hull: '#7a2631', stripe: '#1d1d24', deck: '#7b5a4a', deckLine: '#5c4237', house: '#f3f1ea', accent: '#2f7fd1', flag: ['#e23b3b', '#ffffff'] },
        deckType: 'steel',
        layout: [
          ['brygga', 1, 3],
          ['skorsten', 5, 1],
          ['livbat', 1, 0], ['livbat', 1, 9],
          ['container', 8, 1, { stack: 2 }], ['container', 8, 4, { color: '#2f7fd1' }], ['container', 8, 7, { color: '#e8b021', stack: 2 }],
          ['container', 12, 1, { color: '#3aa357' }], ['container', 12, 7, { color: '#e2632b', stack: 2 }],
          ['container', 16, 1, { color: '#8a4fd1', stack: 2 }], ['container', 16, 7, { color: '#2f7fd1' }],
          ['kista', 13, 4],
          ['kanon', 6, 7], ['kanon', 20, 4],
          ['vatten', 17, 4],
          ['utkik', 5, 4],
          ['vaktkur', 11, 4],
          ['kran', 20, 1],
        ],
        walls: [[12, 3, 4, 'h'], [12, 6, 4, 'h'], [15, 4, 2, 'v']],
      },
      {
        id: 'oljetanker', name: 'Oljetanker', tier: 4,
        story: 'En supertanker med svart guld. Mörsaren på däck kan slå ut hela grupper – sprid ut dina pirater!',
        len: 28, beam: 10, bow: 6, loot: 4000, income: 75, cap: 2400,
        pal: { hull: '#22252c', stripe: '#c0392b', deck: '#6f8a5e', deckLine: '#536a46', house: '#f4f2ec', accent: '#e8b021', flag: ['#13866f', '#f2c14e'] },
        deckType: 'steel',
        layout: [
          ['brygga', 1, 3],
          ['skorsten', 5, 4],
          ['livbat', 1, 0], ['livbat', 1, 9],
          ['ventil', 9, 1], ['ventil', 9, 7], ['ventil', 18, 1], ['ventil', 18, 7],
          ['kista', 13, 3], ['kista', 13, 5],
          ['morsare', 16, 4],
          ['kanon', 7, 4], ['kanon', 22, 4],
          ['vatten', 10, 4], ['ventil', 20, 4],
          ['utkik', 5, 7],
          ['vaktkur', 5, 1],
          ['kran', 14, 0],
        ],
        walls: [[12, 2, 4, 'h'], [12, 7, 4, 'h'], [12, 3, 4, 'v'], [15, 3, 1, 'v'], [15, 6, 1, 'v']],
      },
      {
        id: 'lyxjakt', name: 'Lyxjakt', tier: 5,
        story: 'En miljardärs flytande palats – och kassaskåpen är proppfulla. Säkerhetsvakterna är många.',
        len: 24, beam: 9, bow: 7, loot: 6500, income: 110, cap: 3600,
        pal: { hull: '#f2f4f7', stripe: '#1c2f5a', deck: '#c9955d', deckLine: '#a27245', house: '#ffffff', accent: '#1c2f5a', flag: ['#1c2f5a', '#f2c14e'] },
        deckType: 'wood',
        layout: [
          ['pool', 1, 3],
          ['helipad', 16, 3],
          ['brygga', 9, 2],
          ['kista', 5, 0], ['kista', 5, 7], ['kista', 11, 7], ['kista', 20, 4],
          ['livbat', 1, 0], ['livbat', 1, 8], ['livbat', 9, 0], ['livbat', 11, 0],
          ['utkik', 5, 3], ['utkik', 14, 7],
          ['morsare', 13, 3],
          ['vaktkur', 9, 7], ['vaktkur', 14, 0],
          ['kanon', 17, 1], ['kanon', 19, 6],
          ['vatten', 17, 6],
        ],
        walls: [[8, 1, 6, 'h'], [8, 6, 6, 'h'], [8, 2, 4, 'v'], [13, 2, 1, 'v'], [13, 5, 1, 'v']],
      },
      {
        id: 'krigsskepp', name: 'Krigsskepp', tier: 6,
        story: 'Flottans stolthet. Tre kanoner, två mörsare och matroser överallt. Bara de modigaste kaparna vågar.',
        len: 28, beam: 10, bow: 7, loot: 9000, income: 160, cap: 5000,
        pal: { hull: '#5d6b78', stripe: '#2b3138', deck: '#808d98', deckLine: '#68747e', house: '#a9b4be', accent: '#c8402e', flag: ['#2b3138', '#c8402e'] },
        deckType: 'steel',
        guardType: 'matros',
        layout: [
          ['brygga', 12, 3],
          ['radar', 11, 1], ['radar', 11, 8],
          ['skorsten', 9, 4],
          ['kanon', 2, 4], ['kanon', 17, 1], ['kanon', 21, 4],
          ['morsare', 6, 1], ['morsare', 17, 7],
          ['utkik', 6, 7], ['utkik', 19, 4],
          ['vatten', 14, 0],
          ['vaktkur', 3, 1], ['vaktkur', 3, 7],
          ['kista', 14, 8], ['kista', 9, 7],
          ['livbat', 23, 1]
        ],
        walls: [[11, 2, 6, 'h'], [11, 7, 6, 'h'], [11, 3, 4, 'v'], [16, 3, 4, 'v'], [5, 3, 1, 'v'], [5, 6, 1, 'v']],
      },
    ],
  };
})();
