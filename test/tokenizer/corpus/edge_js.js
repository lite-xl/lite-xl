// line comment
/* block
   comment */
const re = /a[bc]\/d/gi;
const s = "double \" quote", t = 'single \' quote';
const tpl = `sum ${a + b} and ${ {x: 1}.x }`;
class C extends Base {
  #priv = 0;
  async *gen() { yield await Promise.resolve(42); }
}
let n = 0xFF + 1_000 + .5e3 + 3n;
const obj = { "key": [1, 2, 3], get z() { return this.#priv; } };
label: for (const k of Object.keys(obj)) { if (k) continue label; }
