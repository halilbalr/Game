/**
 * Health, hunger, saturation, breath and damage sources. Ticked at 20 Hz.
 */

export class Survival {
  /**
   * @param {object} cfg "survival" section of player.json
   * @param {'peaceful'|'easy'|'normal'|'hard'} difficulty
   */
  constructor(cfg, difficulty = 'normal') {
    this.cfg = cfg;
    this.difficulty = difficulty;
    this.reset();
  }

  /** Full health and food, as on spawn. */
  reset() {
    const c = this.cfg;
    this.health = c.maxHealth;
    this.food = c.maxFood;
    this.saturation = c.startSaturation;
    this.exhaustion = 0;
    this.air = c.maxAirTicks;
    this.dead = false;
    this.invulnerable = 0;
    this._regenTimer = 0;
    this._starveTimer = 0;
    this._drownTimer = 0;
    this._lavaTimer = 0;
    this._contactTimer = 0;
    this.lastDamage = null;
    this.hurtFlash = 0;
  }

  /**
   * Applies damage.
   * @param {number} amount half-hearts
   * @param {string} source cause, e.g. 'fall', 'drown', 'mob'
   * @returns {boolean} whether damage was applied
   */
  damage(amount, source) {
    if (this.dead || amount <= 0) return false;
    if (this.invulnerable > 0 && source !== 'void') return false;
    this.health = Math.max(0, this.health - amount);
    this.invulnerable = this.cfg.invulnerableTicks;
    this.lastDamage = source;
    this.hurtFlash = 1;
    this.addExhaustion(this.cfg.exhaustion.damageTaken);
    if (this.health <= 0) this.dead = true;
    return true;
  }

  heal(amount) {
    if (this.dead) return;
    this.health = Math.min(this.cfg.maxHealth, this.health + amount);
  }

  addExhaustion(v) {
    if (this.difficulty === 'peaceful') return;
    this.exhaustion = Math.min(40, this.exhaustion + v);
  }

  /** Whether the player may eat (not full). */
  canEat() { return this.food < this.cfg.maxFood; }

  /** @param {{hunger:number, saturation:number}} food */
  eat(food) {
    this.food = Math.min(this.cfg.maxFood, this.food + food.hunger);
    this.saturation = Math.min(this.food, this.saturation + food.saturation);
  }

  /** Damage from a landing. */
  onLanded(distance) {
    const d = Math.ceil(distance - this.cfg.fallDamageThreshold);
    if (d > 0) this.damage(d, 'fall');
    return Math.max(0, d);
  }

  /** Whether the player has enough food to sprint. */
  canSprint() { return this.food > this.cfg.sprintMinFood - 1 || this.difficulty === 'peaceful'; }

  /**
   * One game tick.
   * @param {{headInWater:boolean, inLava:boolean, touchingCactus:boolean}} env
   */
  tick(env) {
    if (this.dead) return;
    const c = this.cfg;
    if (this.invulnerable > 0) this.invulnerable--;
    if (this.hurtFlash > 0) this.hurtFlash = Math.max(0, this.hurtFlash - 0.08);

    if (env.headInWater) {
      this.air--;
      if (this.air <= -c.drownIntervalTicks) {
        this.air = 0;
        this.damage(c.drownDamage, 'drown');
      }
    } else {
      this.air = Math.min(c.maxAirTicks, this.air + 4);
    }
    if (env.inLava) {
      if (++this._lavaTimer >= c.lavaIntervalTicks) { this._lavaTimer = 0; this.damage(c.lavaDamage, 'lava'); }
    } else this._lavaTimer = c.lavaIntervalTicks;
    if (env.touchingCactus) {
      if (++this._contactTimer >= c.cactusIntervalTicks) { this._contactTimer = 0; this.damage(1, 'cactus'); }
    } else this._contactTimer = c.cactusIntervalTicks;

    if (this.difficulty === 'peaceful') {
      if (++this._regenTimer >= 20) { this._regenTimer = 0; this.heal(1); }
      this.food = c.maxFood;
      return;
    }

    const ex = c.exhaustion;
    while (this.exhaustion >= ex.threshold) {
      this.exhaustion -= ex.threshold;
      if (this.saturation > 0) this.saturation = Math.max(0, this.saturation - 1);
      else this.food = Math.max(0, this.food - 1);
    }

    if (this.food >= c.maxFood && this.saturation > 0 && this.health < c.maxHealth) {
      if (++this._regenTimer >= 10) {
        this._regenTimer = 0;
        const use = Math.min(this.saturation, ex.regenHeal);
        this.heal(use / ex.regenHeal);
        this.addExhaustion(use);
      }
    } else if (this.food >= c.regenFoodLevel && this.health < c.maxHealth) {
      if (++this._regenTimer >= c.regenIntervalTicks) {
        this._regenTimer = 0;
        this.heal(1);
        this.addExhaustion(ex.regenHeal);
      }
    } else if (this.food <= 0) {
      if (++this._starveTimer >= c.starveIntervalTicks) {
        this._starveTimer = 0;
        const floor = c.starveMinHealth[this.difficulty] ?? 1;
        if (this.health > floor) this.damage(1, 'starve');
      }
    } else {
      this._regenTimer = 0;
    }
  }

  toJSON() {
    return { health: this.health, food: this.food, saturation: this.saturation, exhaustion: this.exhaustion, air: this.air };
  }

  load(d) {
    if (!d) return;
    this.health = d.health ?? this.health;
    this.food = d.food ?? this.food;
    this.saturation = d.saturation ?? this.saturation;
    this.exhaustion = d.exhaustion ?? 0;
    this.air = d.air ?? this.cfg.maxAirTicks;
    this.dead = this.health <= 0;
  }
}
