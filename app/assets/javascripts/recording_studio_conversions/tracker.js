/* Shared tracker. No provider pixels, no page-view counting, no new cookie. */
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.RecordingStudioConversionsTracker = api;
  if (typeof document !== "undefined") api.boot(document, root);
})(typeof globalThis === "undefined" ? this : globalThis, function () {
  function plan(state, input) {
    var next = cloneState(state);
    var config = input.config || { fields: [], modules: [] };
    var urlKey = input.url || "";
    var consentRequest = null;
    if (input.type === "consent") consentRequest = applyConsent(next, input.consent || {});
    var granted = anyGranted(next.consent);
    var body = null;
    var modules = [];
    if (granted) {
      var fields = readFields(
        config.fields || [], next.consent, input.search || "", input.cookie || "", next.collectedFor, urlKey
      );
      if (fields.length || !next.collectedFor[urlMarker(urlKey)]) {
        body = { fields: fields };
        next.collectedFor[urlMarker(urlKey)] = true;
      }
    }
    if (granted) modules = unload(next, input.modules || config.modules || []);
    return { state: next, body: body, modules: modules, consentRequest: consentRequest };
  }

  function applyConsent(state, consent) {
    var category = consent.category;
    if (!category) return null;
    state.consent[category] = consent.granted === true;
    return { category: category, granted: consent.granted === true };
  }

  function readFields(fields, consent, search, cookie, collected, urlKey) {
    if (!anyGranted(consent)) return [];
    var params = new URLSearchParams(search.charAt(0) === "?" ? search.slice(1) : search);
    var cookies = parseCookies(cookie);
    var seen = collected || {};
    return fields.reduce(function (found, field) {
      if (consent[field.consent_category] !== true) return found;
      var key = fieldMarker(urlKey || "", field);
      if (seen[key]) return found;
      var value = field.source === "cookie" ? cookies[field.name] : params.get(field.name);
      if (!value) return found;
      seen[key] = true;
      found.push({ provider: field.provider, name: field.name, value: value });
      return found;
    }, []);
  }

  function urlMarker(url) {
    return "url\n" + url;
  }

  function fieldMarker(url, field) {
    return "field\n" + url + "\n" + field.provider + "\n" + field.name;
  }

  function unload(state, modules) {
    return modules.filter(function (item) {
      if (!item || state.loaded.indexOf(item.name) !== -1) return false;
      state.loaded.push(item.name);
      return true;
    });
  }

  function anyGranted(consent) {
    return Object.keys(consent).some(function (key) { return consent[key] === true; });
  }

  function parseCookies(header) {
    return String(header || "").split(";").reduce(function (parsed, part) {
      var pieces = part.split("=");
      var name = pieces.shift();
      if (!name) return parsed;
      parsed[decodeURIComponent(name.trim())] = decodeURIComponent(pieces.join("=").trim());
      return parsed;
    }, {});
  }

  function cloneState(state) {
    var source = state || { consent: {}, collectedFor: {}, loaded: [] };
    return {
      consent: Object.assign({}, source.consent),
      collectedFor: Object.assign({}, source.collectedFor),
      loaded: source.loaded.slice()
    };
  }

  function boot(doc, win) {
    if (!doc || !win || win.__rsConversionsBooted) return;
    win.__rsConversionsBooted = true;
    var run = function () { visit(doc, win, "turbo"); };
    if (doc.readyState === "loading") doc.addEventListener("DOMContentLoaded", function () { visit(doc, win, "start"); });
    else visit(doc, win, "start");
    doc.addEventListener("turbo:load", run);
    doc.addEventListener("recording-studio-conversions:consent", function (event) {
      onConsent(doc, win, (event && event.detail) || {});
    });
  }

  function visit(doc, win, type) {
    var element = doc.getElementById("recording-studio-conversions");
    if (!element) return;
    var config = parseConfig(element);
    var state = stateFor(win, element);
    var cookie = anyGranted(state.consent) || anyGranted(config.consent || {}) ? doc.cookie || "" : "";
    var planned = plan(mergeConsent(state, config.consent), {
      type: type,
      config: config,
      url: (win.location && (win.location.pathname + win.location.search)) || "",
      search: (win.location && win.location.search) || "",
      cookie: cookie
    });
    remember(win, element, planned.state);
    dispatch(win, config, planned);
  }

  function onConsent(doc, win, detail) {
    var element = doc.getElementById("recording-studio-conversions");
    if (!element || !detail.category) return;
    var config = parseConfig(element);
    var next = cloneState(stateFor(win, element));
    next.consent[detail.category] = detail.granted === true;
    remember(win, element, next);
    postJson(win, config.consent_url, {
      category: detail.category,
      granted: detail.granted === true,
      provenance: { source: "browser" }
    }, csrf(doc)).then(function (response) {
      if (detail.granted !== true) return;
      collectNow(doc, win, element, config, (response && response.modules) || []);
    });
  }

  function collectNow(doc, win, element, config, modules) {
    var planned = plan(stateFor(win, element), {
      type: "start",
      config: config,
      modules: modules,
      url: (win.location && (win.location.pathname + win.location.search)) || "",
      search: (win.location && win.location.search) || "",
      cookie: doc.cookie || ""
    });
    remember(win, element, planned.state);
    dispatch(win, config, planned);
  }

  function mergeConsent(state, pageConsent) {
    var next = cloneState(state);
    Object.keys(pageConsent || {}).forEach(function (key) {
      if (next.consent[key] === undefined) next.consent[key] = pageConsent[key] === true;
    });
    return next;
  }

  function dispatch(win, config, planned) {
    planned.modules.forEach(function (item) { loadModule(win, item); });
    if (planned.body) postJson(win, config.collect_url, planned.body, csrf(win.document));
  }

  function loadModule(win, item) {
    if (!item || !item.src || !win.document) return;
    if (win.document.querySelector('script[data-rs-conversions-module="' + item.name + '"]')) return;
    var script = win.document.createElement("script");
    script.src = item.src;
    script.async = true;
    script.dataset.rsConversionsModule = item.name;
    win.document.head.appendChild(script);
  }

  function postJson(win, url, body, token) {
    if (!url || typeof win.fetch !== "function") return Promise.resolve(null);
    return win.fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token || "" },
      body: JSON.stringify(body)
    }).then(function (response) { return response.json(); }).catch(function () { return null; });
  }

  function stateFor(win, element) {
    win.__rsConversionsStates = win.__rsConversionsStates || {};
    return win.__rsConversionsStates[element.id] || { consent: {}, collectedFor: {}, loaded: [] };
  }

  function remember(win, element, state) {
    win.__rsConversionsStates[element.id] = state;
  }

  function parseConfig(element) {
    try { return JSON.parse(element.getAttribute("data-recording-studio-conversions-config") || "{}"); }
    catch (error) { return { fields: [], modules: [] }; }
  }

  function csrf(doc) {
    if (!doc || !doc.querySelector) return "";
    var tag = doc.querySelector('meta[name="csrf-token"]');
    return tag ? tag.getAttribute("content") : "";
  }

  return { plan: plan, boot: boot, readFields: readFields };
});
