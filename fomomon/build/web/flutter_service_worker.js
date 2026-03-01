'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"favicon.png": "10087efee7b0ed10952f73793b13a018",
"flutter_bootstrap.js": "262ec66a4bfd03d92c99cbfab2ff853b",
"canvaskit/chromium/canvaskit.js.symbols": "5a23598a2a8efd18ec3b60de5d28af8f",
"canvaskit/chromium/canvaskit.js": "34beda9f39eb7d992d46125ca868dc61",
"canvaskit/chromium/canvaskit.wasm": "64a386c87532ae52ae041d18a32a3635",
"canvaskit/skwasm.js": "f2ad9363618c5f62e813740099a80e63",
"canvaskit/canvaskit.js.symbols": "68eb703b9a609baef8ee0e413b442f33",
"canvaskit/skwasm_st.js.symbols": "c7e7aac7cd8b612defd62b43e3050bdd",
"canvaskit/skwasm_st.js": "d1326ceef381ad382ab492ba5d96f04d",
"canvaskit/canvaskit.js": "86e461cf471c1640fd2b461ece4589df",
"canvaskit/skwasm_st.wasm": "56c3973560dfcbf28ce47cebe40f3206",
"canvaskit/skwasm.js.symbols": "80806576fa1056b43dd6d0b445b4b6f7",
"canvaskit/skwasm.wasm": "f0dfd99007f989368db17c9abeed5a49",
"canvaskit/canvaskit.wasm": "efeeba7dcc952dae57870d4df3111fad",
"_redirects": "5f52dbefcf63c9f677ace09fcf8bc7d8",
"version.json": "9165e03bce49e38175ab12da5fe66136",
"main.dart.js": "01fa18f9b5c20da511ef153020965669",
"assets/AssetManifest.bin.json": "e86cc7deb7b92d77beb9b53d1f4d76ac",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.json": "98e7e452a695ff125918c3576fd6413a",
"assets/fonts/MaterialIcons-Regular.otf": "b6a96c1bcfdc4f4ff75b61149daeead2",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/NOTICES": "cc7ecd0a12ee061fc242165efdedb6d1",
"assets/assets/images/loading_icon.png": "80b841add16c1a02c962f1e90c0d2445",
"assets/assets/images/loading.png": "251a3a29258e540be080b371eeb0ceff",
"assets/assets/images/guest_sites/H13R1_2025-03-DSCN2990.JPG": "5ff0f002d1a5ebca271eb67d02127b74",
"assets/assets/images/guest_sites/P1R1_2019-09-DSCN8514.JPG": "c6e85e97ba986df711f03c99d39a6f06",
"assets/assets/images/guest_sites/P1R2_2019-11-DSCN8523.JPG": "922da5363391d54945fada9649139604",
"assets/assets/images/guest_sites/J12R1_2025-03-DSCN2975.JPG": "5c5bdf41f99469f07d5a9efadcbf74fb",
"assets/assets/images/guest_sites/P2R1_2019-11-DSCN8516.JPG": "6d810cf72bc0e39d8ab602f395e0dab1",
"assets/assets/images/guest_sites/P2R2_2022-09-DSCN7780.JPG": "636d7e4540ff5d7411c28cab8aa3eb38",
"assets/assets/images/login.png": "c69959cffc794ea225af97f2a83d5ad9",
"assets/assets/maps/sites.geojson": "a1b3c9a40aa7e6bf5deb4c67e275b180",
"assets/assets/maps/alphaearth_2024_10m.txt": "4ea0e1d3b46c95f898d2675e3827018f",
"assets/assets/maps/alphaearth_2024_10m.png": "fb805e547ebbdda70194c314e862cfae",
"assets/assets/maps/alphaearth_2024_10m.tif": "12938636e5e76f69a4661529b24ddbac",
"assets/assets/maps/sites.kml": "c8d3ccae43c649008d9868b488930d71",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "b83b9a501c1d8ace7a81108f18af13a5",
"icons/Icon-192.png": "08374bd8ad86ed25097bcd2438e9b428",
"icons/Icon-maskable-512.png": "1312c43e49417a636541391de557b0ab",
"icons/Icon-512.png": "1312c43e49417a636541391de557b0ab",
"icons/Icon-maskable-192.png": "08374bd8ad86ed25097bcd2438e9b428",
"index.html": "03b6e26deca454530042d028c7f3e926",
"/": "03b6e26deca454530042d028c7f3e926",
"flutter.js": "76f08d47ff9f5715220992f993002504",
"manifest.json": "00fe22a04093fc49517f9593fca318e5"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
