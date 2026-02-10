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
const refreshBtn = document.getElementById('refresh-btn');
const syncAuthBtn = document.getElementById('sync-auth-btn');

let currentOrg = '';
let sitesData = null;

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

alertClose.addEventListener('click', hideAlert);
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
      bucket_root: `https://fomomon.s3.amazonaws.com/${currentOrg}/`,
      sites: [],
    };
    bucketRootInput.value = sitesData.bucket_root;
    renderSites();
    showAlert(`No sites.json found for ${currentOrg}.`, 'error');
    return;
  }
  sitesData = data.sites_json;
  bucketRootInput.value = sitesData.bucket_root || `https://fomomon.s3.amazonaws.com/${currentOrg}/`;
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
      ? `${bucketRoot}${site.reference_portrait}`
      : '';
    const landscapeUrl = site.reference_landscape
      ? `${bucketRoot}${site.reference_landscape}`
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

loadSitesBtn.addEventListener('click', () => loadSites());
saveSitesBtn.addEventListener('click', () => saveSites());
addSiteBtn.addEventListener('click', () => {
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

sitesUpload.addEventListener('change', async () => {
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

useOrgBtn.addEventListener('click', async () => {
  const selected = orgInput.value.trim() || orgSelect.value;
  if (!selected) return;
  currentOrg = selected;
  orgInput.value = '';
  await refreshAll();
});

refreshBtn.addEventListener('click', refreshAll);

syncAuthBtn.addEventListener('click', async () => {
  try {
    await api('/api/auth_config/sync', { method: 'POST' });
    showAlert('auth_config.json synced.');
  } catch (err) {
    showAlert(err.message, 'error');
  }
});

addUserForm.addEventListener('submit', async (event) => {
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

refreshAll();
