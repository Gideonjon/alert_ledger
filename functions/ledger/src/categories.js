// Two-layer categorisation:
// 1. Fast keyword rules for merchants everyone knows (TOTAL, MTN, PHED...).
// 2. For anything else, nearest-neighbour vote against labelled seed examples
//    stored in the VectorsDB `category_seeds` collection (see vector.js).

export const CATEGORIES = [
  'fuel', 'transport', 'food', 'groceries', 'airtime_data', 'utilities',
  'subscriptions', 'bank_charges', 'rent', 'education', 'health',
  'shopping', 'salary', 'income', 'transfer', 'other',
];

// Words people use in questions → category
export const CATEGORY_SYNONYMS = {
  fuel: ['fuel', 'petrol', 'gas', 'diesel', 'filling station'],
  transport: ['transport', 'uber', 'bolt', 'taxi', 'keke', 'bus', 'ride', 'rides'],
  food: ['food', 'eat', 'eating', 'restaurant', 'chop', 'lunch', 'dinner'],
  groceries: ['groceries', 'grocery', 'supermarket', 'market'],
  airtime_data: ['airtime', 'data', 'recharge'],
  utilities: ['light', 'electricity', 'nepa', 'power', 'utilities', 'dstv', 'gotv', 'cable', 'water'],
  subscriptions: ['subscription', 'subscriptions', 'netflix', 'spotify', 'apple'],
  bank_charges: ['charges', 'bank charges', 'fees', 'sms alert', 'stamp duty'],
  rent: ['rent', 'house'],
  education: ['school', 'fees school', 'tuition', 'education'],
  health: ['hospital', 'pharmacy', 'drugs', 'health'],
  shopping: ['shopping', 'clothes', 'jumia', 'konga'],
  salary: ['salary', 'pay', 'income'],
};

const RULES = [
  ['fuel', /\b(TOTAL\s*ENERGIES|TOTAL|NNPC|MRS|CONOIL|ARDOVA|OANDO|FORTE OIL|MOBIL|FILLING|PETROL|ENERGY STATION)\b/i],
  ['airtime_data', /\b(AIRTIME|DATA\s*(BUNDLE|PLAN)?|MTN|AIRTEL|GLO|9MOBILE|VTU)\b/i],
  ['utilities', /\b(PHED|IKEDC|EKEDC|AEDC|IBEDC|KEDCO|EEDC|BEDC|JED|PREPAID|DSTV|GOTV|STARTIMES|SHOWMAX|ELECTRICITY)\b/i],
  ['transport', /\b(UBER|BOLT|INDRIVE|RIDA|LAGRIDE|GIGM|GUO|ABC TRANSPORT)\b/i],
  ['food', /\b(CHICKEN REPUBLIC|KFC|DOMINOS|CHOWDECK|GLOVO|CHOWWEB|HEYFOOD|COLDSTONE|TANTALIZERS|MR BIGGS|KILIMANJARO|RESTAURANT|EATERY|KITCHEN)\b/i],
  ['groceries', /\b(SHOPRITE|SPAR|JUSTRITE|MARKET SQUARE|PRINCE EBEANO|SUPERMARKET|ROBO)\b/i],
  ['subscriptions', /\b(NETFLIX|SPOTIFY|APPLE\.COM|APPLE COM|GOOGLE\s*\*|YOUTUBE|CHATGPT|OPENAI|ANTHROPIC|CANVA)\b/i],
  ['bank_charges', /\b(SMS\s*ALERT|SMS CHARGE|STAMP\s*DUTY|VAT|COMM(ISSION)?|MAINTENANCE FEE|CARD FEE|ELECTRONIC MONEY TRANSFER LEVY|EMTL)\b/i],
  ['salary', /\b(SALARY|PAYROLL|STIPEND)\b/i],
  ['shopping', /\b(JUMIA|KONGA|TEMU|ALIEXPRESS)\b/i],
  ['transfer', /\b(NIP|TRF|TRANSFER|FIP)\b/i],
];

export function categorizeByKeyword(description) {
  for (const [cat, re] of RULES) if (re.test(description || '')) return cat;
  return null;
}

export function categoryFromWords(text) {
  const t = ` ${String(text).toLowerCase()} `;
  for (const [cat, words] of Object.entries(CATEGORY_SYNONYMS)) {
    if (words.some((w) => t.includes(` ${w} `) || t.includes(` ${w}?`) || t.includes(` ${w}.`))) return cat;
  }
  return null;
}

// Labelled examples loaded into VectorsDB by scripts/setup.mjs.
// These teach the vector layer what unseen merchants "mean".
export const SEED_EXAMPLES = [
  ['fuel', 'POS purchase at petrol filling station'],
  ['fuel', 'bought diesel for generator'],
  ['fuel', 'MRS FILLING STATION POS'],
  ['transport', 'ride hailing trip payment'],
  ['transport', 'keke napep fare transfer'],
  ['transport', 'interstate bus ticket'],
  ['food', 'restaurant meal payment'],
  ['food', 'mama put buka lunch'],
  ['food', 'suya spot dinner'],
  ['food', 'food delivery order'],
  ['groceries', 'supermarket groceries purchase'],
  ['groceries', 'foodstuff market rice beans garri'],
  ['airtime_data', 'mobile airtime recharge'],
  ['airtime_data', 'internet data bundle purchase'],
  ['utilities', 'prepaid electricity meter token'],
  ['utilities', 'cable tv subscription renewal'],
  ['utilities', 'water bill payment'],
  ['subscriptions', 'monthly streaming subscription'],
  ['subscriptions', 'software saas subscription card payment'],
  ['bank_charges', 'bank sms alert charges'],
  ['bank_charges', 'transfer fee and stamp duty'],
  ['rent', 'house rent payment to landlord'],
  ['rent', 'agent fee and caution fee'],
  ['education', 'school fees payment university'],
  ['education', 'online course tuition'],
  ['health', 'pharmacy drugs purchase'],
  ['health', 'hospital bill payment'],
  ['shopping', 'online shopping order clothes'],
  ['shopping', 'phone accessories purchase'],
  ['salary', 'monthly salary credit from employer'],
  ['transfer', 'transfer to friend'],
  ['transfer', 'money sent to family member'],
];
