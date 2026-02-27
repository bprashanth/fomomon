const orgSelect = document.getElementById('org-select');
const orgInput = document.getElementById('org-input');
const useOrgBtn = document.getElementById('use-org-btn');
const orgStatus = document.getElementById('org-status');
const addUserForm = document.getElementById('add-user-form');
const usersList = document.getElementById('users-list');
const allUsers = document.getElementById('all-users');
const statusBar = document.getElementById('status');
const formError = document.getElementById('form-error');
const passwordRules = document.getElementById('password-rules');
const alertBox = document.getElementById('alert');
const alertMessage = document.getElementById('alert-message');
const alertClose = document.getElementById('alert-close');
const loadSitesBtn = document.getElementById('load-sites-btn');
const saveSitesBtn = document.getElementById('save-sites-btn');
const addSiteBtn = document.getElementById('add-site-btn');
const sitesUpload = document.getElementById('sites-upload');
const sitesList = document.getElementById('sites-list');
const bucketRootInput = document.getElementById('bucket-root');
const syncAuthBtn = document.getElementById('sync-auth-btn');
const loadTelemetryBtn = document.getElementById('load-telemetry-btn');
const telemetryStatus = document.getElementById('telemetry-status');
const telemetryTableWrap = document.getElementById('telemetry-table-wrap');

let currentOrg = '';
let sitesData = null;
let config = { bucketRootTemplate: 'https://<bucket>.s3.amazonaws.com/{org}/' };

function setStatus(message, isError = false) {
  statusBar.textContent = message;
  statusBar.style.color = isError ? '#8b2c2c' : '';
}

function setFormError(message) {
  formError.textContent = message || '';
}

function showAlert(message, type = 'success') {
  alertMessage.textContent = message;
  alertBox.classList.remove('hidden', 'error', 'success');
  alertBox.classList.add(type);
}

function hideAlert() {
  alertBox.classList.add('hidden');
}

async function api(path, options = {}) {
  const resp = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(text || resp.statusText);
  }
  return resp.json();
}

alertClose?.addEventListener('click', hideAlert);

function bucketRootForOrg(org) {
  const template = config.bucketRootTemplate || 'https://<bucket>.s3.amazonaws.com/{org}/';
  return template.replace('{org}', org || '');
}

function presignedUrlForKey(key) {
  const encoded = encodeURIComponent(key || '');
  return `/api/s3?key=${encoded}`;
}

async function loadHealth() {
  try {
    const data = await api('/api/health');
    if (!data.ok) {
      setStatus('Prerequisites missing', true);
      showAlert(data.message || 'Server prerequisites not met. Check AWS credentials.', 'error');
      return false;
    }
    return true;
  } catch (err) {
    setStatus('Server not ready', true);
    showAlert(err.message || 'Server not ready. Check backend logs.', 'error');
    return false;
  }
}

async function loadConfig() {
  try {
    const data = await api('/api/config');
    config = data || config;
    bucketRootInput.placeholder = bucketRootForOrg('<org>');
  } catch (err) {
    showAlert(err.message || 'Failed to load server config.', 'error');
  }
}
async function loadPasswordPolicy() {
  const data = await api('/api/password_policy');
  const rules = [];
  if (data.minimumLength) rules.push(`min ${data.minimumLength} chars`);
  if (data.requireUppercase) rules.push('1 uppercase');
  if (data.requireLowercase) rules.push('1 lowercase');
  if (data.requireNumbers) rules.push('1 number');
  if (data.requireSymbols) rules.push('1 symbol');
  if (rules.length) {
    passwordRules.textContent = `Password rules: ${rules.join(', ')}.`;
  } else {
    passwordRules.textContent = 'Password rules: follow Cognito pool policy.';
  }
}

async function loadOrgs() {
  const data = await api('/api/orgs');
  orgSelect.innerHTML = '';
  data.orgs.forEach((org) => {
    const opt = document.createElement('option');
    opt.value = org;
    opt.textContent = org;
    orgSelect.appendChild(opt);
  });
  if (!currentOrg && data.orgs.length) {
    currentOrg = data.orgs[0];
  }
  orgSelect.value = currentOrg;
  orgStatus.textContent = currentOrg ? `Using org: ${currentOrg}` : 'No org selected yet.';
}

async function loadOrgUsers() {
  usersList.innerHTML = '';
  if (!currentOrg) {
    usersList.textContent = 'Pick or create an org to see users.';
    return;
  }
  const data = await api(`/api/orgs/${encodeURIComponent(currentOrg)}/users`);
  if (!data.users.length) {
    usersList.textContent = 'No users mapped to this org yet.';
    return;
  }
  data.users.forEach((row) => {
    const item = document.createElement('div');
    item.className = 'list-item';
    const profile = row.profile || {};
    const cognito = row.cognito || {};
    item.innerHTML = `
      <div class="meta">
        <strong>${profile.name || 'Unknown'}</strong>
        <span class="muted">${profile.email || ''}</span>
        <span class="muted">username: ${profile.username || profile.user_id || profile.email || ''}</span>
        <span class="muted">password: ${profile.password || ''}</span>
        <span class="muted">cognito: ${cognito.status || 'n/a'} ${cognito.enabled === false ? '(disabled)' : ''}</span>
      </div>
      <div class="actions">
        <button class="secondary" data-action="reset" data-username="${profile.username}">Reset Password</button>
        <button data-action="delete" data-username="${profile.username}">Delete</button>
      </div>
    `;
    usersList.appendChild(item);
  });

  usersList.querySelectorAll('button').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const action = btn.dataset.action;
      const username = btn.dataset.username;
      if (!username) return;
      if (action === 'delete') {
        if (!confirm(`Delete ${username} from ${currentOrg}?`)) return;
        await api(`/api/orgs/${encodeURIComponent(currentOrg)}/users/${encodeURIComponent(username)}`, {
          method: 'DELETE',
        });
        await refreshAll();
        showAlert(`Deleted ${username}.`);
      }
      if (action === 'reset') {
        const password = prompt('New password');
        if (!password) return;
        await api(`/api/orgs/${encodeURIComponent(currentOrg)}/users/${encodeURIComponent(username)}/password`, {
          method: 'PUT',
          body: JSON.stringify({ password }),
        });
        showAlert(`Password updated for ${username}.`);
      }
    });
  });
}

async function loadAllUsers() {
  allUsers.innerHTML = '';
  const data = await api('/api/users');
  data.users.forEach((user) => {
    const item = document.createElement('div');
    item.className = 'list-item';
    item.innerHTML = `
      <div class="meta">
        <strong>${user.name || user.email || user.username}</strong>
        <span class="muted">${user.email || ''}</span>
        <span class="muted">username: ${user.username}</span>
        <span class="muted">status: ${user.status || ''}</span>
      </div>
    `;
    allUsers.appendChild(item);
  });
}

async function loadSites() {
  if (!currentOrg) {
    showAlert('Select an org first.', 'error');
    return;
  }
  const data = await api(`/api/orgs/${encodeURIComponent(currentOrg)}/sites`);
  if (!data.sites_json) {
    sitesData = {
      bucket_root: bucketRootForOrg(currentOrg),
      sites: [],
    };
    bucketRootInput.value = sitesData.bucket_root;
    renderSites();
    showAlert(`No sites.json found for ${currentOrg}.`, 'error');
    return;
  }
  sitesData = data.sites_json;
  bucketRootInput.value = sitesData.bucket_root || bucketRootForOrg(currentOrg);
  renderSites();
  showAlert(`Loaded sites.json for ${currentOrg}.`);
}

async function saveSites() {
  if (!currentOrg) {
    showAlert('Select an org first.', 'error');
    return;
  }
  if (!sitesData) {
    showAlert('No sites loaded.', 'error');
    return;
  }
  sitesData.bucket_root = bucketRootInput.value.trim();
  await api(`/api/orgs/${encodeURIComponent(currentOrg)}/sites`, {
    method: 'PUT',
    body: JSON.stringify({ sites_json: sitesData }),
  });
  showAlert(`Saved sites.json for ${currentOrg}.`);
}

function renderSites() {
  sitesList.innerHTML = '';
  if (!sitesData || !sitesData.sites || !sitesData.sites.length) {
    sitesList.textContent = 'No sites yet.';
    return;
  }
  sitesData.sites.forEach((site, index) => {
    const card = document.createElement('div');
    card.className = 'site-card';
    const bucketRoot = (bucketRootInput.value || '').replace(/\/+$/, '') + '/';
    const portraitUrl = site.reference_portrait
      ? presignedUrlForKey(`${currentOrg}/${site.reference_portrait}`)
      : '';
    const landscapeUrl = site.reference_landscape
      ? presignedUrlForKey(`${currentOrg}/${site.reference_landscape}`)
      : '';

    card.innerHTML = `
      <div class="row">
        <label>
          Site ID
          <input data-field="id" data-index="${index}" value="${site.id || ''}" />
        </label>
        <label>
          Lat
          <input data-field="lat" data-index="${index}" value="${site.location?.lat ?? ''}" />
        </label>
        <label>
          Lng
          <input data-field="lng" data-index="${index}" value="${site.location?.lng ?? ''}" />
        </label>
      </div>
      <div class="row">
        <div>
          <div class="muted">Portrait</div>
          ${portraitUrl ? `<img src="${portraitUrl}" alt="portrait" />` : '<div class="muted">No image</div>'}
          <div class="row">
            <input type="file" data-orientation="portrait" data-index="${index}" accept="image/*" />
            <button class="secondary" data-action="upload" data-orientation="portrait" data-index="${index}">Upload</button>
          </div>
        </div>
        <div>
          <div class="muted">Landscape</div>
          ${landscapeUrl ? `<img src="${landscapeUrl}" alt="landscape" />` : '<div class="muted">No image</div>'}
          <div class="row">
            <input type="file" data-orientation="landscape" data-index="${index}" accept="image/*" />
            <button class="secondary" data-action="upload" data-orientation="landscape" data-index="${index}">Upload</button>
          </div>
        </div>
      </div>
      <label>
        Reference Portrait Path
        <input data-field="reference_portrait" data-index="${index}" value="${site.reference_portrait || ''}" />
      </label>
      <label>
        Reference Landscape Path
        <input data-field="reference_landscape" data-index="${index}" value="${site.reference_landscape || ''}" />
      </label>
      <label>
        Survey JSON
        <textarea data-field="survey" data-index="${index}" rows="4" spellcheck="false">${JSON.stringify(site.survey || [], null, 2)}</textarea>
      </label>
      <button data-action="delete-site" data-index="${index}">Delete Site</button>
    `;

    sitesList.appendChild(card);
  });

  sitesList.querySelectorAll('input[data-field], textarea[data-field]').forEach((input) => {
    input.addEventListener('change', () => {
      const index = Number(input.dataset.index);
      const field = input.dataset.field;
      const site = sitesData.sites[index];
      if (!site) return;
      if (field === 'lat' || field === 'lng') {
        site.location = site.location || {};
        site.location[field] = Number(input.value);
      } else if (field === 'survey') {
        try {
          site.survey = JSON.parse(input.value);
        } catch (err) {
          showAlert(`Survey JSON invalid for ${site.id || 'site'}: ${err.message}`, 'error');
        }
      } else {
        site[field] = input.value;
      }
    });
  });

  sitesList.querySelectorAll('button[data-action="delete-site"]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const index = Number(btn.dataset.index);
      sitesData.sites.splice(index, 1);
      renderSites();
    });
  });

  sitesList.querySelectorAll('button[data-action="upload"]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const index = Number(btn.dataset.index);
      const orientation = btn.dataset.orientation;
      const fileInput = sitesList.querySelector(
        `input[type="file"][data-orientation="${orientation}"][data-index="${index}"]`
      );
      if (!fileInput || !fileInput.files.length) {
        showAlert('Select an image first.', 'error');
        return;
      }
      const site = sitesData.sites[index];
      const form = new FormData();
      form.append('site_id', site.id);
      form.append('orientation', orientation);
      form.append('image', fileInput.files[0]);
      try {
        const resp = await fetch(`/api/orgs/${encodeURIComponent(currentOrg)}/ghosts`, {
          method: 'POST',
          body: form,
        });
        if (!resp.ok) {
          const text = await resp.text();
          throw new Error(text || resp.statusText);
        }
        const data = await resp.json();
        if (orientation === 'portrait') {
          site.reference_portrait = data.relative_path;
        } else {
          site.reference_landscape = data.relative_path;
        }
        renderSites();
        showAlert('Ghost image uploaded. Save to persist sites.json.');
      } catch (err) {
        showAlert(err.message, 'error');
      } finally {
        fileInput.value = '';
      }
    });
  });
}

loadSitesBtn?.addEventListener('click', () => loadSites());
saveSitesBtn?.addEventListener('click', () => saveSites());
addSiteBtn?.addEventListener('click', () => {
  if (!sitesData) {
    sitesData = { bucket_root: bucketRootInput.value || '', sites: [] };
  }
  sitesData.sites.push({
    id: '',
    location: { lat: 0, lng: 0 },
    creation_timestamp: new Date().toISOString(),
    reference_portrait: '',
    reference_landscape: '',
    survey: [],
  });
  renderSites();
});

sitesUpload?.addEventListener('change', async () => {
  if (!currentOrg) {
    showAlert('Select an org first.', 'error');
    return;
  }
  if (!sitesUpload.files.length) return;
  const form = new FormData();
  form.append('file', sitesUpload.files[0]);
  try {
    const resp = await fetch(`/api/orgs/${encodeURIComponent(currentOrg)}/sites/upload`, {
      method: 'POST',
      body: form,
    });
    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(text || resp.statusText);
    }
    showAlert(`Uploaded sites.json for ${currentOrg}.`);
    await loadSites();
  } catch (err) {
    showAlert(err.message, 'error');
  } finally {
    sitesUpload.value = '';
  }
});

async function loadTelemetry() {
  if (!currentOrg) {
    showAlert('Select an org first.', 'error');
    return;
  }
  telemetryStatus.textContent = 'Loading…';
  telemetryTableWrap.innerHTML = '';
  try {
    const data = await api(`/api/orgs/${encodeURIComponent(currentOrg)}/telemetry`);
    renderTelemetry(data);
    telemetryStatus.textContent =
      `${data.events.length} events · ${data.files_fetched} file(s) · ${(data.bytes_fetched / 1024).toFixed(1)} KB`;
  } catch (err) {
    telemetryStatus.textContent = '';
    showAlert(err.message, 'error');
  }
}

function renderTelemetry(data) {
  if (!data.events || !data.events.length) {
    telemetryTableWrap.innerHTML = '<p class="muted">No telemetry events in the last 7 days.</p>';
    return;
  }
  const rows = data.events.map((e) => {
    const levelClass = e.level === 'error' ? 'tel-error' : e.level === 'warning' ? 'tel-warning' : 'tel-info';
    const ts = (e.timestamp || '').replace('T', ' ').replace('Z', '');
    const ctx = e.context ? JSON.stringify(e.context, null, 2) : '';
    const ctxHtml = ctx
      ? `<details><summary>ctx</summary><pre>${ctx}</pre></details>`
      : '—';
    const userId = e._userId ? `<span class="muted">${e._userId}</span>` : '';
    return `<tr class="${levelClass}">
      <td class="tel-ts">${ts}${userId ? '<br>' + userId : ''}</td>
      <td class="tel-level">${e.level || ''}</td>
      <td class="tel-pivot">${e.pivot || ''}</td>
      <td>${e.message || ''}${e.error ? `<br><span class="muted">${e.error}</span>` : ''}</td>
      <td>${ctxHtml}</td>
    </tr>`;
  }).join('');
  telemetryTableWrap.innerHTML = `
    <div class="tel-scroll">
      <table class="tel-table">
        <thead><tr><th>Time / User</th><th>Level</th><th>Pivot</th><th>Message</th><th>Context</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

loadTelemetryBtn?.addEventListener('click', () => loadTelemetry());

async function refreshAll() {
  try {
    await loadOrgs();
    await loadOrgUsers();
    await loadAllUsers();
    await loadPasswordPolicy();
    setStatus('Ready.');
  } catch (err) {
    setStatus(err.message, true);
  }
}

useOrgBtn?.addEventListener('click', async () => {
  const selected = orgInput.value.trim() || orgSelect.value;
  if (!selected) return;
  currentOrg = selected;
  orgInput.value = '';
  try {
    const prov = await api(`/api/orgs/${encodeURIComponent(currentOrg)}/provision`, { method: 'POST' });
    const ruleMsg = prov.lifecycle_rule_created ? ' Lifecycle rule created.' : ' Lifecycle rule already in place.';
    showAlert(`Org "${currentOrg}" provisioned.${ruleMsg}`);
  } catch (err) {
    showAlert(`Provision failed for "${currentOrg}": ${err.message}`, 'error');
  }
  await refreshAll();
});


syncAuthBtn?.addEventListener('click', async () => {
  try {
    const resp = await fetch('/api/auth_config/sync', { method: 'POST' });
    const data = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      if (data && data.commands && data.example_auth_config) {
        const lines = [
          data.message || 'Setup required.',
          '',
          'Steps:',
          ...(data.steps || []).map((s) => `- ${s}`),
          '',
          'Commands:',
          ...(data.commands || []),
          '',
          'Example auth_config.json:',
          JSON.stringify(data.example_auth_config, null, 2),
        ];
        alert(lines.join('\\n'));
        return;
      }
      throw new Error(data.detail || 'Unable to sync auth_config.json.');
    }
    const bucketStatus = data.bucketPolicyChanged ? 'changed' : 'no change';
    const roleStatus = data.rolePolicyChanged ? 'changed' : 'no change';
    showAlert(`Permissions enforced. Bucket policy: ${bucketStatus}. Role policy: ${roleStatus}.`);
  } catch (err) {
    showAlert(err.message, 'error');
  }
});

addUserForm?.addEventListener('submit', async (event) => {
  event.preventDefault();
  setFormError('');
  if (!currentOrg) {
    showAlert('Select an org first.', 'error');
    return;
  }
  const formData = new FormData(addUserForm);
  const payload = {
    org: currentOrg,
    name: formData.get('name') || '',
    email: formData.get('email') || '',
    password: formData.get('password') || '',
  };
  try {
    const data = await api(`/api/orgs/${encodeURIComponent(currentOrg)}/users`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    addUserForm.reset();
    await refreshAll();
    showAlert(data.created ? 'User created.' : 'User existed; password updated.');
  } catch (err) {
    let message = err.message || 'Unable to add user.';
    try {
      const parsed = JSON.parse(message);
      if (parsed.detail) message = parsed.detail;
    } catch {
      // ignore
    }
    setFormError(message);
    showAlert(message, 'error');
  }
});

(async () => {
  const healthy = await loadHealth();
  await loadConfig();
  if (healthy) {
    await refreshAll();
  }
})();
