const assert = require("node:assert/strict");
const tracker = require(process.argv[2]);

const fields = [
  { provider: "catalog", name: "click_id", source: "query_parameter", consent_category: "advertising" },
  { provider: "catalog", name: "browser_id", source: "cookie", consent_category: "advertising" },
  { provider: "catalog", name: "campaign", source: "query_parameter", consent_category: "analytics" }
];
const config = { fields: fields, modules: [{ name: "fake-ads", src: "/modules/fake-ads" }] };

const blocked = tracker.plan({ consent: {}, collectedFor: {}, loaded: [] }, {
  type: "start",
  config: config,
  url: "/pricing",
  search: "?click_id=abc",
  cookie: "browser_id=from-cookie"
});
assert.equal(blocked.body, null);
assert.deepEqual(blocked.modules, []);

const first = tracker.plan({ consent: { advertising: true }, collectedFor: {}, loaded: [] }, {
  type: "start",
  config: config,
  url: "/pricing",
  search: "?click_id=abc",
  cookie: "browser_id=from-cookie"
});
assert.deepEqual(first.body.fields, [
  { provider: "catalog", name: "click_id", value: "abc" },
  { provider: "catalog", name: "browser_id", value: "from-cookie" }
]);
assert.equal(first.modules.length, 1);

const missingCookie = tracker.plan({ consent: { advertising: true }, collectedFor: {}, loaded: [] }, {
  type: "start",
  config: config,
  url: "/pricing",
  search: "?click_id=abc",
  cookie: ""
});
assert.deepEqual(missingCookie.body.fields, [{ provider: "catalog", name: "click_id", value: "abc" }]);

const duplicate = tracker.plan(first.state, {
  type: "start",
  config: config,
  url: "/pricing",
  search: "?click_id=abc",
  cookie: "browser_id=from-cookie"
});
assert.equal(duplicate.body, null);
assert.deepEqual(duplicate.modules, []);

const turboSame = tracker.plan(first.state, { type: "turbo", config: config, url: "/pricing", search: "", cookie: "" });
assert.equal(turboSame.body, null);

const turboNext = tracker.plan(first.state, {
  type: "turbo",
  config: config,
  url: "/pricing?click_id=next",
  search: "?click_id=next",
  cookie: ""
});
assert.equal(turboNext.body.fields[0].value, "next");

const secondCategory = tracker.plan(first.state, {
  type: "consent",
  config: config,
  consent: { category: "analytics", granted: true },
  url: "/pricing",
  search: "?click_id=abc&campaign=spring",
  cookie: "browser_id=from-cookie"
});
assert.equal(secondCategory.state.consent.analytics, true);
assert.deepEqual(secondCategory.body.fields, [
  { provider: "catalog", name: "campaign", value: "spring" }
]);
assert.equal(secondCategory.state.collectedFor["url\n/pricing"], true);
assert.equal(secondCategory.state.collectedFor["field\n/pricing\ncatalog\nclick_id"], true);

const grantedAgain = tracker.plan(secondCategory.state, {
  type: "consent",
  config: config,
  consent: { category: "advertising", granted: true },
  url: "/pricing",
  search: "?click_id=abc&campaign=spring",
  cookie: "browser_id=from-cookie"
});
assert.equal(grantedAgain.body, null);

const withdrawn = tracker.plan(first.state, {
  type: "consent",
  config: config,
  consent: { category: "advertising", granted: false },
  url: "/pricing",
  search: "?click_id=abc",
  cookie: "browser_id=from-cookie"
});
assert.equal(withdrawn.state.consent.advertising, false);
assert.equal(withdrawn.body, null);
assert.equal(withdrawn.consentRequest.granted, false);

const fetches = [];
const doc = {
  readyState: "complete",
  cookie: "browser_id=from-cookie",
  listeners: {},
  head: { appendChild() {} },
  element: {
    id: "recording-studio-conversions",
    getAttribute() {
      return JSON.stringify({
        fields: fields,
        modules: [],
        consent: { advertising: true },
        collect_url: "/recording_studio_conversions/collection",
        consent_url: "/recording_studio_conversions/consent"
      });
    }
  },
  addEventListener(name, fn) {
    this.listeners[name] = this.listeners[name] || [];
    this.listeners[name].push(fn);
  },
  getElementById() { return this.element; },
  querySelector() { return null; },
  createElement() { return { dataset: {} }; }
};
const win = {
  location: { pathname: "/pricing", search: "?click_id=abc" },
  document: doc,
  fetch(_url, options) {
    fetches.push(JSON.parse(options.body));
    return Promise.resolve({ json() { return Promise.resolve({ modules: [] }); } });
  }
};
tracker.boot(doc, win);
tracker.boot(doc, win);
assert.equal(doc.listeners["turbo:load"].length, 1);
assert.equal(fetches.length, 1);
doc.listeners["turbo:load"][0]();
assert.equal(fetches.length, 1);
win.location = { pathname: "/pricing", search: "?click_id=later" };
doc.listeners["turbo:load"][0]();
assert.equal(fetches.length, 2);
assert.equal(fetches[1].fields[0].value, "later");

const laterFetches = [];
const laterDoc = {
  readyState: "complete",
  cookie: "browser_id=from-cookie",
  listeners: {},
  head: { appendChild() {} },
  element: {
    id: "recording-studio-conversions",
    getAttribute() {
      return JSON.stringify({
        fields: fields,
        modules: [],
        consent: { advertising: true },
        collect_url: "/recording_studio_conversions/collection",
        consent_url: "/recording_studio_conversions/consent"
      });
    }
  },
  addEventListener(name, fn) {
    this.listeners[name] = this.listeners[name] || [];
    this.listeners[name].push(fn);
  },
  getElementById() { return this.element; },
  querySelector() { return null; },
  createElement() { return { dataset: {} }; }
};
const laterWin = {
  location: { pathname: "/pricing", search: "?click_id=abc&campaign=spring" },
  document: laterDoc,
  fetch(_url, options) {
    laterFetches.push(JSON.parse(options.body));
    return Promise.resolve({ json() { return Promise.resolve({ modules: [] }); } });
  }
};
tracker.boot(laterDoc, laterWin);
assert.deepEqual(laterFetches[0].fields.map((field) => field.name), ["click_id", "browser_id"]);
laterDoc.listeners["recording-studio-conversions:consent"][0]({
  detail: { category: "analytics", granted: true }
});

setTimeout(() => {
  try {
    const collection = laterFetches.filter((body) => Array.isArray(body.fields));
    assert.equal(collection.length, 2);
    assert.deepEqual(collection[1].fields, [
      { provider: "catalog", name: "campaign", value: "spring" }
    ]);
    console.log("browser tracker script ok");
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}, 0);
