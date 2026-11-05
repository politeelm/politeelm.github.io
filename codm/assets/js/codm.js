/* ==========================================================================
   wiki.js —— 索引、搜索、分类、条目页、[[双链]]、反向链接
   --------------------------------------------------------------------------
   #/                 索引（全部条目，按首字分组）
   #/tag/奇异人士      只看某个分类
   #/e/<slug>         条目页
   ========================================================================== */

(function () {
  "use strict";

  var cfg = window.WIKI_CONFIG || {};
  var app = document.getElementById("app");

  /* ------------------------------ 工具 ------------------------------ */

  function escapeHtml(v) {
    return String(v == null ? "" : v)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function stripTags(html) {
    return String(html || "")
      .replace(/<[^>]*>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function fmtDate(iso) {
    var p = String(iso || "").split("-");
    if (p.length !== 3) return iso || "";
    return p[0] + " 年 " + Number(p[1]) + " 月 " + Number(p[2]) + " 日";
  }

  /* ------------------------------ 数据 ------------------------------ */

  var entries = (window.WIKI_ENTRIES || []).map(function (e) {
    return {
      slug: e.slug,
      title: e.title || "无标题",
      tags: e.tags || [],
      desc: e.desc || e.summary || stripTags(e.content).slice(0, 70),
      recap: e.recap || "",
      content: e.content || "",
      date: e.date || "",
      plain: stripTags(e.content)
    };
  });

  entries.sort(function (a, b) {
    return a.title.localeCompare(b.title, "zh-Hans-CN");
  });

  function bySlug(slug) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].slug === slug) return entries[i];
    }
    return null;
  }

  function byTitle(title) {
    var t = String(title || "").trim();
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].title === t) return entries[i];
    }
    return null;
  }

  var allTags = (function () {
    var map = {};
    entries.forEach(function (e) {
      e.tags.forEach(function (t) {
        map[t] = (map[t] || 0) + 1;
      });
    });
    return Object.keys(map)
      .map(function (t) {
        return { name: t, count: map[t] };
      })
      .sort(function (a, b) {
        return b.count - a.count || a.name.localeCompare(b.name);
      });
  })();

  /* ------------------------------ 路由 ------------------------------ */

  function parseHash() {
    var raw = (location.hash || "").replace(/^#\/?/, "");
    if (!raw) return { view: "home", tag: "" };

    var parts = raw.split("/");

    if (parts[0] === "e" && parts[1]) {
      return { view: "entry", slug: decodeURIComponent(parts.slice(1).join("/")) };
    }
    if (parts[0] === "tag" && parts[1]) {
      return { view: "home", tag: decodeURIComponent(parts.slice(1).join("/")) };
    }
    return { view: "home", tag: "" };
  }

  /* ------------------------------ 双链 ------------------------------ */

  function renderWikilinks(html) {
    return String(html || "").replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, function (m, target, label) {
      var text = (label || target).trim();
      var found = byTitle(target.trim());
      if (found) {
        return (
          '<a class="wikilink" href="#/e/' + encodeURIComponent(found.slug) + '">' +
          escapeHtml(text) +
          "</a>"
        );
      }
      return '<span class="wikilink is-new" title="还没有这个条目">' + escapeHtml(text) + "</span>";
    });
  }

  function backlinks(entry) {
    var out = [];
    entries.forEach(function (other) {
      if (other.slug === entry.slug) return;
      var re = new RegExp("\\[\\[" + entry.title.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "(\\||\\]\\])");
      if (re.test(other.content)) out.push(other);
    });
    return out;
  }

  function related(entry) {
    if (!entry.tags.length) return [];
    var out = [];
    entries.forEach(function (other) {
      if (other.slug === entry.slug) return;
      var shared = other.tags.some(function (t) {
        return entry.tags.indexOf(t) !== -1;
      });
      if (shared) out.push(other);
    });
    return out.slice(0, 8);
  }

  /* ------------------------------ 计数 ------------------------------ */

  function catCounterHtml() {
    var moe = cfg.catCounter || "";
    if (!moe) return "";

    var fallback =
      "https://hits.sh/" + (cfg.hitPath || "politeelm.github.io/wiki") +
      "/index.svg?label=" + encodeURIComponent("访问") + "&color=b0492b&style=flat";

    return (
      '<div class="cat-counter">' +
        '<img src="' + escapeHtml(moe) + '" alt="访问量" loading="lazy" ' +
          'referrerpolicy="no-referrer" data-fallback="' + escapeHtml(fallback) + '">' +
      "</div>"
    );
  }

  function readCounterHtml(slug) {
    var src =
      "https://hits.sh/" + (cfg.hitPath || "politeelm.github.io/wiki") +
      "/" + (/^post-|^e-/.test(slug) ? "" : "e-") + encodeURIComponent(slug) +
      ".svg?label=" + encodeURIComponent("阅读") + "&color=b0492b&style=flat";

    return '<span class="read-count"><img src="' + src + '" alt="阅读量" loading="lazy" referrerpolicy="no-referrer"></span>';
  }

  function mountCounters() {
    var imgs = document.querySelectorAll(".cat-counter img, .read-count img");
    for (var i = 0; i < imgs.length; i++) {
      (function (img) {
        function fail() {
          var fb = img.getAttribute("data-fallback");
          if (fb && img.getAttribute("src") !== fb) {
            img.setAttribute("src", fb);
            return;
          }
          var box = img.parentNode;
          if (box) box.style.display = "none";
        }
        img.addEventListener("error", fail);
        if (img.complete && img.naturalWidth === 0) fail();
      })(imgs[i]);
    }
  }

  /* ------------------------------ 索引页 ------------------------------ */

  function firstChar(title) {
    var ch = String(title || "").trim().charAt(0);
    if (!ch) return "#";
    if (/[a-zA-Z]/.test(ch)) return ch.toUpperCase();
    if (/[0-9]/.test(ch)) return "0-9";
    return ch;
  }

  function indexListHtml(list) {
    if (!list.length) {
      return (
        '<div class="empty">' +
          "<p>还没有条目。</p>" +
          "<p>用桌面上的「新建条目」加第一条，或者换个关键词搜搜看。</p>" +
        "</div>"
      );
    }

    var groups = {};
    list.forEach(function (e) {
      var k = firstChar(e.title);
      (groups[k] = groups[k] || []).push(e);
    });

    var keys = Object.keys(groups).sort(function (a, b) {
      if (a === "0-9") return -1;
      if (b === "0-9") return 1;
      return a.localeCompare(b, "zh-Hans-CN");
    });

    return keys
      .map(function (k) {
        return (
          '<section class="index-group">' +
            '<h2 class="index-letter">' + escapeHtml(k) + "</h2>" +
            '<ul class="entry-list">' +
              groups[k]
                .map(function (e) {
                  return (
                    "<li>" +
                      '<a href="#/e/' + encodeURIComponent(e.slug) + '">' +
                        '<span class="entry-name">' + escapeHtml(e.title) + "</span>" +
                        '<span class="entry-desc">' + escapeHtml(e.desc || "") + "</span>" +
                      "</a>" +
                    "</li>"
                  );
                })
                .join("") +
            "</ul>" +
          "</section>"
        );
      })
      .join("");
  }

  function chipsHtml(tag) {
    var all = '<a class="chip' + (tag ? "" : " is-active") + '" href="#/">全部<span class="chip-count">' + entries.length + "</span></a>";
    var rest = allTags
      .map(function (t) {
        var active = t.name === tag ? " is-active" : "";
        return (
          '<a class="chip' + active + '" href="#/tag/' + encodeURIComponent(t.name) + '">' +
          escapeHtml(t.name) +
          '<span class="chip-count">' + t.count + "</span></a>"
        );
      })
      .join("");
    return all + rest;
  }

  function renderHome(route) {
    var list = entries;
    if (route.tag) {
      list = entries.filter(function (e) {
        return e.tags.indexOf(route.tag) !== -1;
      });
    }

    app.innerHTML =
      '<section class="hero">' +
        "<h1>" + escapeHtml(cfg.title || "收集录") + "</h1>" +
        "<p>" + escapeHtml(cfg.intro || "") + "</p>" +
        catCounterHtml() +
      "</section>" +
      '<section class="listing">' +
        '<div class="toolbar">' +
          '<label class="search">' +
            '<span class="search-icon" aria-hidden="true">⌕</span>' +
            '<input id="q" type="search" autocomplete="off" spellcheck="false" placeholder="搜索条目…（按 / 聚焦）">' +
          "</label>" +
        "</div>" +
        '<div class="chips" id="chips">' + chipsHtml(route.tag) + "</div>" +
        '<p class="index-meta" id="meta"></p>' +
        '<div id="results">' + indexListHtml(list) + "</div>" +
      "</section>";

    updateMeta(list.length, route.tag);
    bindSearch(route);
  }

  function updateMeta(count, tag) {
    var meta = document.getElementById("meta");
    if (!meta) return;
    var bits = ["共 " + count + " 条"];
    if (tag) bits.push("分类「" + tag + "」");
    bits.push("最后整理 " + fmtDate(new Date().toISOString().slice(0, 10)));
    meta.innerHTML = bits
      .map(function (b) {
        return "<span>" + escapeHtml(b) + "</span>";
      })
      .join('<span class="sep">·</span>');
  }

  function bindSearch(route) {
    var input = document.getElementById("q");
    var results = document.getElementById("results");
    var meta = document.getElementById("meta");
    if (!input) return;

    var timer = null;

    input.addEventListener("input", function () {
      clearTimeout(timer);
      timer = setTimeout(function () {
        var q = input.value.trim().toLowerCase();
        var base = entries.filter(function (e) {
          return !route.tag || e.tags.indexOf(route.tag) !== -1;
        });
        var list = q
          ? base.filter(function (e) {
              return (e.title + " " + e.desc + " " + e.plain).toLowerCase().indexOf(q) !== -1;
            })
          : base;

        results.innerHTML = indexListHtml(list);
        if (meta) {
          meta.innerHTML =
            "<span>共 " + list.length + " 条</span>" +
            (route.tag ? '<span class="sep">·</span><span>分类「' + escapeHtml(route.tag) + "」</span>" : "") +
            (q ? '<span class="sep">·</span><span>搜索「' + escapeHtml(input.value.trim()) + "」</span>" : "");
        }
      }, 140);
    });

    document.addEventListener("keydown", function (ev) {
      if (ev.key === "/" && document.activeElement !== input) {
        var tag = document.activeElement && document.activeElement.tagName;
        if (tag === "INPUT" || tag === "TEXTAREA") return;
        ev.preventDefault();
        input.focus();
      }
    });
  }

  /* ------------------------------ 条目页 ------------------------------ */

  function renderEntry(route) {
    var entry = bySlug(route.slug);

    if (!entry) {
      app.innerHTML =
        '<section class="entry-page">' +
          '<span class="empty" style="display:block">' +
            "<p>这个条目不存在，可能已经被删掉或者链接写错了。</p>" +
            '<a class="breadcrumb" href="#/">← 回到索引</a>' +
          "</span>" +
        "</section>";
      return;
    }

    var bl = backlinks(entry);
    var rel = related(entry);

    app.innerHTML =
      '<article class="entry-page">' +
        '<a class="breadcrumb" href="#/">← 索引</a>' +
        "<h1 class=\"entry-title\">" + escapeHtml(entry.title) + "</h1>" +
        '<div class="entry-meta">' +
          (entry.tags.length
            ? entry.tags
                .map(function (t) {
                  return '<a class="chip" href="#/tag/' + encodeURIComponent(t) + '">' + escapeHtml(t) + "</a>";
                })
                .join("")
            : "") +
          (entry.date ? "<span>" + escapeHtml(fmtDate(entry.date)) + "</span>" : "") +
          readCounterHtml(entry.slug) +
        "</div>" +
        '<section class="entry-section">' +
          '<h2 class="section-title">神人事迹</h2>' +
          '<div class="desc-box">' + (entry.desc ? escapeHtml(entry.desc) : "（未填写）") + "</div>" +
        "</section>" +
        '<section class="entry-section">' +
          '<h2 class="section-title">简单回顾</h2>' +
          '<div class="recap-box">' +
            (String(entry.recap || "").trim()
              ? renderWikilinks(entry.recap)
              : '<p class="no-content">暂时没有</p>') +
          "</div>" +
        "</section>" +
        '<section class="entry-section">' +
          '<h2 class="section-title">长篇大论</h2>' +
          '<div class="prose">' +
            (String(entry.content || "").trim()
              ? renderWikilinks(entry.content)
              : '<p class="no-content">暂时没有</p>') +
          "</div>" +
        "</section>" +
        '<p class="entry-contact">投稿：<a href="mailto:' + escapeHtml(cfg.contact || "steamryy@outlook.com") + '">' +
          escapeHtml(cfg.contact || "steamryy@outlook.com") + "</a></p>" +
        '<div class="entry-foot">' +
          (bl.length
            ? "<h2>哪些条目提到了它</h2>" +
              '<ul class="link-list">' +
              bl
                .map(function (o) {
                  return '<li><a href="#/e/' + encodeURIComponent(o.slug) + '">' + escapeHtml(o.title) + "</a></li>";
                })
                .join("") +
              "</ul>"
            : "") +
          (rel.length
            ? "<h2>同类条目</h2>" +
              '<ul class="link-list">' +
              rel
                .map(function (o) {
                  return '<li><a href="#/e/' + encodeURIComponent(o.slug) + '">' + escapeHtml(o.title) + "</a></li>";
                })
                .join("") +
              "</ul>"
            : "") +
        "</div>" +
      "</article>";
  }

  /* ------------------------------ 渲染 ------------------------------ */

  function render() {
    var route = parseHash();

    if (route.view === "entry") {
      renderEntry(route);
      var e = bySlug(route.slug);
      document.title = (e ? e.title : "条目不存在") + " · " + (cfg.title || "收集录");
    } else {
      renderHome(route);
      document.title = (cfg.title || "收集录") + (route.tag ? " · " + route.tag : "");
    }

    var brandLetters = document.querySelectorAll("[data-nav]");
    for (var i = 0; i < brandLetters.length; i++) {
      var isHome = brandLetters[i].getAttribute("data-nav") === "home";
      if (isHome && !route.tag) brandLetters[i].setAttribute("aria-current", "page");
      else brandLetters[i].removeAttribute("aria-current");
    }

    mountCounters();
    window.scrollTo(0, 0);
  }

  /* ------------------------------ 图片放大 ------------------------------ */

  var lightbox = null;

  function ensureLightbox() {
    if (lightbox) return lightbox;
    lightbox = document.createElement("div");
    lightbox.className = "lightbox";
    lightbox.innerHTML =
      '<button class="lightbox-close" type="button" aria-label="关闭（Esc）">×</button><img alt="">';
    lightbox.addEventListener("click", function (ev) {
      if (ev.target === lightbox || ev.target.classList.contains("lightbox-close")) closeLightbox();
    });
    document.body.appendChild(lightbox);
    return lightbox;
  }

  function openLightbox(src, alt) {
    var box = ensureLightbox();
    var im = box.querySelector("img");
    im.setAttribute("src", src);
    im.setAttribute("alt", alt || "");
    box.classList.add("is-open");
    document.documentElement.style.overflow = "hidden";
  }

  function closeLightbox() {
    if (!lightbox) return;
    lightbox.classList.remove("is-open");
    document.documentElement.style.overflow = "";
  }

  document.addEventListener("click", function (ev) {
    var img = ev.target;
    if (!img || img.tagName !== "IMG") return;
    if (!img.closest || !img.closest(".prose")) return;
    var src = img.getAttribute("src");
    if (!src) return;
    ev.preventDefault();
    openLightbox(src, img.getAttribute("alt"));
  });

  document.addEventListener("keydown", function (ev) {
    if (ev.key === "Escape") {
      closeLightbox();
      if (document.activeElement && document.activeElement.id === "q") {
        document.activeElement.value = "";
        document.activeElement.blur();
      }
    }
  });

  /* ------------------------------ 主题 ------------------------------ */

  var root = document.documentElement;
  var toggle = document.querySelector(".theme-toggle");

  function syncTheme() {
    if (!toggle) return;
    var dark = root.getAttribute("data-theme") === "dark";
    toggle.textContent = dark ? "☀" : "☾";
    toggle.setAttribute("aria-label", dark ? "切换到浅色模式" : "切换到深色模式");
  }

  if (toggle) {
    syncTheme();
    toggle.addEventListener("click", function () {
      var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try {
        localStorage.setItem("theme", next);
      } catch (e) {}
      syncTheme();
    });
  }

  var years = document.querySelectorAll("[data-year]");
  for (var i = 0; i < years.length; i++) {
    years[i].textContent = String(new Date().getFullYear());
  }

  /* ------------------------------ 启动 ------------------------------ */

  window.addEventListener("hashchange", render);

  if (!location.hash) history.replaceState(null, "", "#/");

  render();
})();
