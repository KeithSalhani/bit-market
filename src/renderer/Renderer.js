import { COLORS, shelfColor, shelfBorderColor } from './colors.js';

/**
 * Renderer – draws the entire Bit-Market simulation onto an HTML5 Canvas
 * using a bright, playful "Toy-Store" visual style.
 */
export class Renderer {
  /**
   * @param {HTMLCanvasElement} canvas
   */
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this._frameOffset = 0; // used for animated effects
  }

  /**
   * Render one frame.
   * @param {import('../Simulation.js').Simulation} simulation
   */
  render(simulation) {
    this._frameOffset += 1;
    const ctx = this.ctx;
    const { store, shoppers, storeBots, clerks } = simulation;

    this._drawBackground(store);
    this._drawShelves(store.shelves);
    this._drawCheckouts(store.checkouts);
    this._drawEntrance(store);

    // Draw entities in back-to-front order
    storeBots.forEach((b) => this._drawStoreBot(b));
    clerks.forEach((c) => this._drawClerk(c));
    shoppers.forEach((s) => this._drawShopper(s));

    this._drawHUD(simulation);
  }

  // ─── Background ────────────────────────────────────────────────────────────

  _drawBackground(store) {
    const ctx = this.ctx;
    const { width, height } = store;

    // Base fill
    ctx.fillStyle = COLORS.background;
    ctx.fillRect(0, 0, width, height);

    // Checkered floor tiles
    const tileSize = 40;
    for (let y = 0; y < height; y += tileSize) {
      for (let x = 0; x < width; x += tileSize) {
        const isEven = ((x / tileSize) + (y / tileSize)) % 2 === 0;
        ctx.fillStyle = isEven ? COLORS.floorA : COLORS.floorB;
        ctx.fillRect(x, y, tileSize, tileSize);
      }
    }

    // Colourful top border / canopy
    const grad = ctx.createLinearGradient(0, 0, width, 0);
    grad.addColorStop(0, '#FF6B6B');
    grad.addColorStop(0.33, '#FECA57');
    grad.addColorStop(0.66, '#48DBFB');
    grad.addColorStop(1, '#FF9FF3');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, width, 14);

    // Warehouse label strip at the very top
    ctx.fillStyle = 'rgba(0,0,0,0.08)';
    ctx.fillRect(0, 0, width, 50);
    ctx.fillStyle = COLORS.textDark;
    ctx.font = 'bold 11px monospace';
    ctx.textAlign = 'center';
    ctx.fillText('🏭 WAREHOUSE', width / 2, 30);
  }

  // ─── Shelves ───────────────────────────────────────────────────────────────

  _drawShelves(shelves) {
    shelves.forEach((shelf) => this._drawShelf(shelf));
  }

  _drawShelf(shelf) {
    const ctx = this.ctx;
    const { x, y, width, height, category, product, stock, maxCapacity } = shelf;

    // Shadow
    ctx.shadowColor = 'rgba(0,0,0,0.15)';
    ctx.shadowBlur = 6;
    ctx.shadowOffsetY = 3;

    // Background
    this._roundRect(x, y, width, height, 10, shelfColor(category));

    // Border
    ctx.strokeStyle = shelfBorderColor(category);
    ctx.lineWidth = 3;
    ctx.stroke();

    ctx.shadowColor = 'transparent';
    ctx.shadowBlur = 0;
    ctx.shadowOffsetY = 0;

    // Category label
    ctx.fillStyle = shelfBorderColor(category);
    ctx.font = 'bold 10px sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText(category.toUpperCase(), x + 6, y + 13);

    if (!product) return;

    // Product emoji
    ctx.font = '22px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(product.emoji, x + width / 2, y + height / 2 + 6);

    // Stock bar
    const barW = width - 16;
    const barH = 6;
    const barX = x + 8;
    const barY = y + height - 12;
    ctx.fillStyle = '#DFE6E9';
    this._roundRect(barX, barY, barW, barH, 3, '#DFE6E9');

    const ratio = stock / maxCapacity;
    const fillColor =
      ratio > 0.6 ? '#00B894' : ratio > 0.3 ? '#FDCB6E' : '#D63031';
    this._roundRect(barX, barY, barW * ratio, barH, 3, fillColor);

    // Price tag
    const price = product.price;
    ctx.fillStyle = COLORS.priceBg;
    const tagW = 44;
    const tagH = 16;
    const tagX = x + width - tagW - 4;
    const tagY = y + 4;
    this._roundRect(tagX, tagY, tagW, tagH, 4, COLORS.priceBg);
    ctx.fillStyle = '#6C5CE7';
    ctx.font = 'bold 9px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(`$${price.toFixed(0)}`, tagX + tagW / 2, tagY + 11);
  }

  // ─── Checkouts ────────────────────────────────────────────────────────────

  _drawCheckouts(checkouts) {
    checkouts.forEach((co) => this._drawCheckout(co));
  }

  _drawCheckout(co) {
    const ctx = this.ctx;
    const { x, y, width, height } = co;

    ctx.shadowColor = 'rgba(0,0,0,0.2)';
    ctx.shadowBlur = 8;
    ctx.shadowOffsetY = 4;

    // Counter body
    this._roundRect(x, y, width, height, 10, COLORS.checkoutBg);
    ctx.strokeStyle = COLORS.checkoutBorder;
    ctx.lineWidth = 3;
    ctx.stroke();

    ctx.shadowColor = 'transparent';
    ctx.shadowBlur = 0;
    ctx.shadowOffsetY = 0;

    // Animated conveyor belt stripes
    const stripeW = 10;
    const offset = (this._frameOffset * 0.5) % (stripeW * 2);
    ctx.save();
    ctx.beginPath();
    ctx.rect(x + 6, y + height / 2, width - 12, height / 2 - 6);
    ctx.clip();
    ctx.fillStyle = COLORS.conveyorBelt;
    ctx.fillRect(x + 6, y + height / 2, width - 12, height / 2 - 6);
    for (let bx = x + 6 - offset; bx < x + width; bx += stripeW * 2) {
      ctx.fillStyle = 'rgba(0,0,0,0.07)';
      ctx.fillRect(bx, y + height / 2, stripeW, height / 2 - 6);
    }
    ctx.restore();

    // Label
    ctx.fillStyle = COLORS.textDark;
    ctx.font = 'bold 11px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(`🛒 ${co.id.replace('-', ' ').toUpperCase()}`, x + width / 2, y + 20);

    // Queue length indicator
    if (co.queueLength > 0) {
      ctx.fillStyle = '#E17055';
      ctx.font = 'bold 10px sans-serif';
      ctx.fillText(`Queue: ${co.queueLength}`, x + width / 2, y + 34);
    }
  }

  // ─── Entrance ─────────────────────────────────────────────────────────────

  _drawEntrance(store) {
    const ctx = this.ctx;
    const ex = store.entranceX;
    const ey = store.entranceY;

    // Doors
    const doorW = 60;
    const doorH = 40;
    ctx.fillStyle = '#74B9FF';
    ctx.strokeStyle = '#0984E3';
    ctx.lineWidth = 3;
    this._roundRect(ex - doorW - 5, ey - doorH / 2, doorW, doorH, 6, '#74B9FF');
    ctx.stroke();
    this._roundRect(ex + 5, ey - doorH / 2, doorW, doorH, 6, '#74B9FF');
    ctx.stroke();

    // Entrance label
    ctx.fillStyle = COLORS.textDark;
    ctx.font = 'bold 13px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('🚪 ENTRANCE / EXIT', ex, ey + doorH / 2 + 16);
  }

  // ─── Entities ─────────────────────────────────────────────────────────────

  _drawShopper(shopper) {
    const ctx = this.ctx;
    const { x, y, radius, color, cart, happiness } = shopper;

    ctx.shadowColor = 'rgba(0,0,0,0.2)';
    ctx.shadowBlur = 6;

    // Body
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.strokeStyle = COLORS.shopperStroke;
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.shadowColor = 'transparent';
    ctx.shadowBlur = 0;

    // Face expression based on happiness
    const face = happiness >= 70 ? '😊' : happiness >= 40 ? '😐' : '😟';
    ctx.font = `${radius}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.fillText(face, x, y + radius / 3);

    // Cart indicator
    if (cart.length > 0) {
      ctx.fillStyle = '#FFEAA7';
      ctx.strokeStyle = '#FDCB6E';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(x + radius - 2, y - radius + 2, 7, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = COLORS.textDark;
      ctx.font = 'bold 8px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(cart.length, x + radius - 2, y - radius + 5);
    }
  }

  _drawStoreBot(bot) {
    const ctx = this.ctx;
    const { x, y, radius, carryAmount, carryCapacity } = bot;

    ctx.shadowColor = 'rgba(0,0,0,0.2)';
    ctx.shadowBlur = 5;

    // Robot body (rounded square)
    const s = radius * 1.6;
    this._roundRect(x - s / 2, y - s / 2, s, s, 5, bot.color);
    ctx.strokeStyle = bot.accentColor;
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.shadowColor = 'transparent';
    ctx.shadowBlur = 0;

    // Antenna
    ctx.strokeStyle = bot.accentColor;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(x, y - s / 2);
    ctx.lineTo(x, y - s / 2 - 8);
    ctx.stroke();
    ctx.fillStyle = '#FF6B6B';
    ctx.beginPath();
    ctx.arc(x, y - s / 2 - 8, 3, 0, Math.PI * 2);
    ctx.fill();

    // Eyes
    ctx.fillStyle = bot.accentColor;
    ctx.beginPath();
    ctx.arc(x - 5, y - 3, 3, 0, Math.PI * 2);
    ctx.arc(x + 5, y - 3, 3, 0, Math.PI * 2);
    ctx.fill();

    // Carry indicator
    if (carryAmount > 0) {
      ctx.fillStyle = '#00CEC9';
      ctx.font = 'bold 9px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(`📦${carryAmount}`, x, y + s / 2 + 12);
    }

    // State label
    ctx.fillStyle = bot.accentColor;
    ctx.font = '8px monospace';
    ctx.textAlign = 'center';
    const state = bot.stateMachine ? bot.stateMachine.current : '';
    ctx.fillText(state, x, y + s / 2 + 22);
  }

  _drawClerk(clerk) {
    const ctx = this.ctx;
    const { x, y, radius, color } = clerk;

    // Body
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.strokeStyle = COLORS.clerkStroke;
    ctx.lineWidth = 2;
    ctx.stroke();

    // Hat (a small rounded rect above the circle)
    const hatW = radius * 1.6;
    const hatH = 8;
    this._roundRect(x - hatW / 2, y - radius - hatH, hatW, hatH, 3, COLORS.clerkStroke);

    // Emoji face
    ctx.font = `${radius}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.fillText('👤', x, y + radius / 3);
  }

  // ─── HUD / Stats overlay ──────────────────────────────────────────────────

  _drawHUD(simulation) {
    const ctx = this.ctx;
    const stats = simulation.getStats();
    const { width } = simulation.store;

    const panelW = 200;
    const panelH = 115;
    const px = width - panelW - 10;
    const py = 18;

    // Panel background
    ctx.fillStyle = COLORS.panelBg;
    this._roundRect(px, py, panelW, panelH, 10, COLORS.panelBg);

    ctx.font = 'bold 13px sans-serif';
    ctx.textAlign = 'left';
    ctx.fillStyle = '#FFFFFF';
    ctx.fillText('📊 BIT-MARKET STATS', px + 10, py + 18);

    const rows = [
      [`⏱ Tick`,    stats.tick],
      [`🛒 Shoppers`, stats.shoppers],
      [`🤖 Bots`,    stats.bots],
      [`💰 Revenue`,  `$${stats.revenue.toFixed(0)}`],
      [`✅ Served`,   stats.served],
    ];

    ctx.font = '11px sans-serif';
    rows.forEach(([label, value], i) => {
      const ry = py + 34 + i * 16;
      ctx.fillStyle = COLORS.statLabel;
      ctx.fillText(label, px + 10, ry);
      ctx.fillStyle = COLORS.statValue;
      ctx.textAlign = 'right';
      ctx.fillText(String(value), px + panelW - 10, ry);
      ctx.textAlign = 'left';
    });
  }

  // ─── Utility ──────────────────────────────────────────────────────────────

  /**
   * Draw a filled rounded rectangle and leave the path ready for stroking.
   * @param {number} x @param {number} y @param {number} w @param {number} h
   * @param {number} r Radius  @param {string} fill Fill colour
   */
  _roundRect(x, y, w, h, r, fill) {
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.arcTo(x + w, y, x + w, y + r, r);
    ctx.lineTo(x + w, y + h - r);
    ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
    ctx.lineTo(x + r, y + h);
    ctx.arcTo(x, y + h, x, y + h - r, r);
    ctx.lineTo(x, y + r);
    ctx.arcTo(x, y, x + r, y, r);
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
  }
}
