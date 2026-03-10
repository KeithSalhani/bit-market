/**
 * Toy-Store colour palette used throughout the Bit-Market renderer.
 * Bright, saturated colours with a playful candy-shop feel.
 */
export const COLORS = {
  // Background & floor
  background: '#FFF9E6',
  floorA: '#EBF5FB',
  floorB: '#FDFEFE',
  wall: '#FF6B6B',

  // Shelf category tints
  shelfToys:        '#FFB3B3',
  shelfFood:        '#FFE4A0',
  shelfElectronics: '#A9D0F5',
  shelfSports:      '#ABEBC6',

  shelfBorder: {
    toys:        '#E74C3C',
    food:        '#F39C12',
    electronics: '#2980B9',
    sports:      '#27AE60',
  },

  // Entity colours
  shopperStroke: '#2C3E50',
  botBody: '#C8D6E5',
  botAccent: '#576574',
  clerkBody: '#6C5CE7',
  clerkStroke: '#341F97',

  // Checkout
  checkoutBg: '#F8C291',
  checkoutBorder: '#E55039',
  conveyorBelt: '#BDC3C7',

  // Text
  textDark: '#2C3E50',
  textLight: '#FFFFFF',
  priceBg: '#FFEAA7',

  // UI panel
  panelBg: 'rgba(44,62,80,0.85)',
  statLabel: '#BDC3C7',
  statValue: '#F9CA24',
};

/**
 * Map a shelf category to its background tint colour.
 * @param {string} category
 * @returns {string} CSS colour string
 */
export function shelfColor(category) {
  switch (category) {
    case 'toys':        return COLORS.shelfToys;
    case 'food':        return COLORS.shelfFood;
    case 'electronics': return COLORS.shelfElectronics;
    case 'sports':      return COLORS.shelfSports;
    default:            return '#ECF0F1';
  }
}

/**
 * Map a category to its shelf border/accent colour.
 * @param {string} category
 * @returns {string} CSS colour string
 */
export function shelfBorderColor(category) {
  return COLORS.shelfBorder[category] ?? '#95A5A6';
}
