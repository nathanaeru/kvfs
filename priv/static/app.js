let currentOwner = 'alice';
let currentPath = [];
let selectedItem = null;
let selectedType = null;
let modalResolver = null;
let modalMode = null;

// Initialize Workspace
document.addEventListener('DOMContentLoaded', () => {
    initializeModal();
    initWebSocket();
    loadDirectory();
    updateQuota();
});

function initializeModal() {
    const dialog = document.getElementById('appModal');
    const form = document.getElementById('appModalForm');

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        const value = modalMode === 'prompt'
            ? (document.getElementById('appModalTextarea').classList.contains('hidden')
                ? document.getElementById('appModalInput').value
                : document.getElementById('appModalTextarea').value)
            : true;
        finishModal(value);
    });

    document.getElementById('appModalCancel').addEventListener('click', () => {
        finishModal(modalMode === 'prompt' ? null : false);
    });

    dialog.addEventListener('cancel', (event) => {
        event.preventDefault();
        finishModal(modalMode === 'prompt' ? null : false);
    });
}

function showModal({ title, message = '', mode = 'alert', defaultValue = '', multiline = false }) {
    const dialog = document.getElementById('appModal');
    const inputContainer = document.getElementById('appModalInputContainer');
    const input = document.getElementById('appModalInput');
    const textarea = document.getElementById('appModalTextarea');
    const cancelButton = document.getElementById('appModalCancel');

    modalMode = mode;
    document.getElementById('appModalTitle').textContent = title;
    document.getElementById('appModalMessage').textContent = message;
    document.getElementById('appModalSubmit').textContent = mode === 'confirm' ? 'Delete' : 'OK';
    cancelButton.hidden = mode === 'alert';
    inputContainer.classList.toggle('hidden', mode !== 'prompt');
    input.hidden = multiline;
    textarea.classList.toggle('hidden', !multiline);
    input.value = multiline ? '' : defaultValue;
    textarea.value = multiline ? defaultValue : '';

    return new Promise((resolve) => {
        modalResolver = resolve;
        dialog.showModal();
        if (mode === 'prompt') {
            (multiline ? textarea : input).focus();
        } else {
            document.getElementById('appModalSubmit').focus();
        }
    });
}

function finishModal(value) {
    const dialog = document.getElementById('appModal');
    const resolve = modalResolver;
    modalResolver = null;
    modalMode = null;
    dialog.close();
    if (resolve) resolve(value);
}

// Real-time WebSocket Handler
function initWebSocket() {
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(`${protocol}//${location.host}/ws`);

    ws.onopen = () => {
        document.getElementById('wsStatus').innerText = 'Active';
        document.getElementById('wsStatus').className = 'text-emerald-600';
    };

    ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data.event === 'tree_updated') {
            loadDirectory();
            updateQuota();
        }
    };

    ws.onclose = () => {
        document.getElementById('wsStatus').innerText = 'Disconnected';
        document.getElementById('wsStatus').className = 'text-red-600';
        setTimeout(initWebSocket, 3000);
    };
}

// REST API Operations
async function loadDirectory() {
    clearSelection();
    const pathStr = currentPath.length > 0 ? '/' + currentPath.join('/') : '';
    renderBreadcrumb();

    try {
        const res = await fetch(`/api/list/${currentOwner}${pathStr}`);
        const data = await res.json();

        if (data.status === 'ok') {
            renderFileList(data.entries);
        } else {
            document.getElementById('fileList').innerHTML = `<div class="p-4 text-slate-500 italic">Empty or directory not found.</div>`;
        }
    } catch (err) {
        console.error('Failed to load directory:', err);
    }
}

function renderFileList(entries) {
    const container = document.getElementById('fileList');
    if (!entries || entries.length === 0) {
        container.innerHTML = `<div class="p-4 text-slate-500 italic">Folder is empty.</div>`;
        return;
    }

    container.innerHTML = entries.map(item => {
        const isDir = item.type === 'directory';
        const icon = isDir ? '📁' : '📄';
        const sizeStr = isDir ? '-' : `${item.size || 0} B`;
        const displayType = isDir ? item.type : (item.mime_type || 'text/plain');
        const safeDisplayType = escapeHtml(displayType);
        const tagsStr = item.tags ? item.tags.map(t => `<span class="bg-slate-100 text-emerald-700 px-1.5 py-0.5 rounded text-[10px]">${t}</span>`).join(' ') : '-';

        return `
            <div onclick="selectRow(this, '${item.name}', '${item.type}')"
                 ondblclick="handleDblClick('${item.name}', '${item.type}')" 
                 class="grid grid-cols-12 gap-2 p-2 hover:bg-slate-100 rounded cursor-pointer border border-transparent hover:border-slate-200 text-slate-700 items-center">
                <div class="col-span-5 flex items-center gap-2 font-semibold">
                    <span>${icon}</span>
                    <span class="truncate">${item.name}</span>
                </div>
                <div class="col-span-2 truncate text-slate-500" title="${safeDisplayType}">${safeDisplayType}</div>
                <div class="col-span-2 text-slate-500">${sizeStr}</div>
                <div class="col-span-3 flex gap-1 overflow-x-auto">${tagsStr}</div>
            </div>
        `;
    }).join('');
}

function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (character) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    })[character]);
}

function renderBreadcrumb() {
    const el = document.getElementById('breadcrumb');
    let html = `<span onclick="navigateTo([])" class="text-emerald-600 font-bold cursor-pointer hover:underline">/${currentOwner}</span>`;
    
    let accPath = [];
    currentPath.forEach(part => {
        accPath.push(part);
        const pathTarget = [...accPath];
        html += `<span class="text-slate-400">/</span><span onclick="navigateTo(['${pathTarget.join("','")}'])" class="cursor-pointer hover:underline text-slate-700">${part}</span>`;
    });

    el.innerHTML = html;
}

function navigateTo(pathArray) {
    currentPath = pathArray;
    loadDirectory();
}

function navigateUp() {
    if (currentPath.length > 0) {
        currentPath.pop();
        loadDirectory();
    }
}

function refreshCurrentDir() {
    loadDirectory();
    updateQuota();
}

function handleDblClick(name, type) {
    if (type === 'directory') {
        currentPath.push(name);
        loadDirectory();
    } else {
        viewFileContent(name);
    }
}

// Actions & Creation
async function promptNewFolder() {
    const name = await showModal({ title: 'New Folder', message: 'Enter folder name:', mode: 'prompt' });
    if (!name) return;

    const pathArr = [...currentPath, name];
    await fetch(`/api/file/${currentOwner}/${pathArr.join('/')}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'directory' })
    });
    loadDirectory();
}

async function promptNewFile() {
    const name = await showModal({ title: 'New File', message: 'Enter file name (e.g. notes.txt):', mode: 'prompt' });
    if (!name) return;
    const mimeType = await showModal({
        title: 'File Type',
        message: 'Enter the file MIME type (e.g. application/json):',
        mode: 'prompt',
        defaultValue: 'text/plain'
    });
    const content = await showModal({
        title: 'File Content',
        message: 'Enter file content:',
        mode: 'prompt',
        defaultValue: 'Sample text',
        multiline: true
    });
    const tagsInput = await showModal({
        title: 'File Tags',
        message: 'Enter tags comma separated:',
        mode: 'prompt',
        defaultValue: 'fp,urgent'
    });
    const tags = tagsInput ? tagsInput.split(',').map(t => t.trim()) : [];

    const pathArr = [...currentPath, name];
    await fetch(`/api/file/${currentOwner}/${pathArr.join('/')}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            type: 'file',
            content: content || '',
            tags: tags,
            mime_type: mimeType || 'text/plain'
        })
    });
    loadDirectory();
}

async function viewFileContent(filename, pathArr = [...currentPath, filename], owner = currentOwner) {
    const path = pathArr.map(component => encodeURIComponent(component)).join('/');
    const res = await fetch(`/api/file/${encodeURIComponent(owner)}/${path}`);
    const data = await res.json();
    if (data.status === 'ok') {
        await showModal({
            title: `📄 File: ${filename}`,
            message: `Type: ${data.data.mime_type || 'text/plain'}\n\nContent:\n${data.data.content}\n\nTags: ${data.data.tags ? data.data.tags.join(', ') : 'None'}`
        });
    }
}

async function searchTag() {
    clearSelection();
    const tag = document.getElementById('tagSearchInput').value.trim();
    if (!tag) {
        loadDirectory();
        return;
    }

    const res = await fetch(`/api/search/tag?tag=${encodeURIComponent(tag)}`);
    const data = await res.json();
    
    if (data.status === 'ok') {
        const container = document.getElementById('fileList');
        if (data.matches.length === 0) {
            container.innerHTML = `<div class="p-4 text-amber-400 italic">No files matching tag '${tag}' found in ETS index.</div>`;
            return;
        }

        container.innerHTML = data.matches.map((item, index) => `
            <div data-match-index="${index}" class="grid grid-cols-12 gap-2 p-2 bg-slate-50 rounded border border-emerald-200 text-slate-700 items-center cursor-pointer">
                <div class="col-span-5 flex items-center gap-2 font-mono text-emerald-700 font-bold">
                    <span>📄</span>
                    <span>${item.path.join('/')}</span>
                </div>
                <div class="col-span-4 text-slate-500 font-mono">Matched via ETS Index</div>
                <div class="col-span-3 font-mono text-xs text-emerald-700">Tag: ${tag}</div>
            </div>
        `).join('');

        container.querySelectorAll('[data-match-index]').forEach((row, index) => {
            const item = data.matches[index];
            row.title = 'Double-click to open file';
            row.addEventListener('dblclick', () => {
                viewFileContent(item.path[item.path.length - 1], item.path, item.owner);
            });
        });
    }
}

async function updateQuota() {
    try {
        const res = await fetch(`/api/quota/${currentOwner}`);
        const data = await res.json();
        if (data.status === 'ok') {
            const q = data.quota;
            document.getElementById('quotaBadge').innerHTML = `
                <span>Storage: <strong>${q.total_bytes || 0} Bytes</strong></span>
                <span>|</span>
                <span>Files: <strong>${q.file_count || 0}</strong></span>
            `;

            // Update ETS Live Monitors View
            document.getElementById('etsQuotaView').innerHTML = `
                <div class="font-bold border-b border-slate-200 pb-1 mb-1 text-slate-600">ETS Table: kvfs_user_quota</div>
                <pre class="text-[10px]">${JSON.stringify(q, null, 2)}</pre>
            `;
        }
        
        // Fetch All Tag Indexes for Monitor
        const tagRes = await fetch(`/api/search/tag?tag=fp`);
        const tagData = await tagRes.json();
        document.getElementById('etsTagIndexView').innerHTML = `
            <div class="font-bold border-b border-slate-200 pb-1 mb-1 text-slate-600">ETS Table: kvfs_tag_index (Sample Tag: 'fp')</div>
            <pre class="text-[10px]">${JSON.stringify(tagData, null, 2)}</pre>
        `;
    } catch (err) {
        console.error('Quota update error:', err);
    }
}

function selectRow(element, name, type) {
    document.querySelectorAll('#fileList > div').forEach(el => el.classList.remove('bg-slate-100', 'border-slate-300'));
    element.classList.add('bg-slate-100', 'border-slate-300');
    selectedItem = name;
    selectedType = type;
    document.getElementById('moveSelectedButton').disabled = false;
    document.getElementById('copySelectedButton').disabled = false;
    document.getElementById('deleteSelectedButton').disabled = false;
}

function clearSelection() {
    selectedItem = null;
    selectedType = null;
    document.getElementById('moveSelectedButton').disabled = true;
    document.getElementById('copySelectedButton').disabled = true;
    document.getElementById('deleteSelectedButton').disabled = true;
}

async function moveSelectedItem() {
    await transferSelectedItem('move');
}

async function copySelectedItem() {
    await transferSelectedItem('copy');
}

async function transferSelectedItem(action) {
    if (!selectedItem) return;

    const sourcePath = [...currentPath, selectedItem];
    const pathLabel = `/${currentOwner}/${sourcePath.join('/')}`;
    const destination = await showModal({
        title: action === 'move' ? 'Move Item' : 'Copy Item',
        message: `Enter a destination path relative to /${currentOwner}. An existing directory keeps the original name; otherwise the final path is used as the new name.`,
        mode: 'prompt'
    });
    if (destination === null) return;

    let destinationPath = destination.trim().replace(/^\/+|\/+$/g, '');
    if (destinationPath === currentOwner) destinationPath = '';
    else if (destinationPath.startsWith(`${currentOwner}/`)) {
        destinationPath = destinationPath.slice(currentOwner.length + 1);
    }

    const destinationParts = destinationPath.split('/').filter(Boolean);
    if (destinationParts.length === 0) {
        await showModal({ title: 'Invalid Destination', message: 'Enter a destination path.' });
        return;
    }

    const isSamePath = sourcePath.length === destinationParts.length
        && sourcePath.every((part, index) => part === destinationParts[index]);
    const isSameDirectory = sourcePath.length === destinationParts.length + 1
        && sourcePath.slice(0, -1).every((part, index) => part === destinationParts[index]);
    const isInsideSourceDirectory = selectedType === 'directory'
        && destinationParts.length > sourcePath.length
        && sourcePath.every((part, index) => part === destinationParts[index]);
    if (isSamePath || isSameDirectory || isInsideSourceDirectory) {
        await showModal({
            title: 'Invalid Destination',
            message: 'Choose a destination different from the selected item and its current directory.'
        });
        return;
    }

    try {
        const res = await fetch(`/api/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                owner: currentOwner,
                src: sourcePath,
                dst: destinationParts
            })
        });
        const responseBody = await res.text();
        const hasBody = responseBody.trim().length > 0;
        let data = null;
        if (hasBody) {
            try {
                data = JSON.parse(responseBody);
            } catch {
                throw new Error(`Invalid server response (HTTP ${res.status})`);
            }
        }
        if (!res.ok || (hasBody && data?.status !== 'ok')) {
            throw new Error(data?.reason || `HTTP ${res.status}`);
        }

        await Promise.all([loadDirectory(), updateQuota()]);
    } catch (err) {
        console.error(`Failed to ${action} path:`, err);
        await showModal({
            title: `${action === 'move' ? 'Move' : 'Copy'} Failed`,
            message: `Failed to ${action} "${pathLabel}": ${err.message}`
        });
    }
}

async function deleteSelectedItem() {
    if (!selectedItem) return;

    const itemPath = [...currentPath, selectedItem];
    const pathLabel = `/${currentOwner}/${itemPath.join('/')}`;
    if (!await showModal({
        title: 'Delete Item',
        message: `Delete "${pathLabel}"? This cannot be undone.`,
        mode: 'confirm'
    })) return;

    try {
        const path = itemPath.map(component => encodeURIComponent(component)).join('/');
        const res = await fetch(`/api/file/${encodeURIComponent(currentOwner)}/${path}`, {
            method: 'DELETE'
        });
        const data = await res.json();

        if (!res.ok || data.status !== 'ok') {
            throw new Error(data.reason || `HTTP ${res.status}`);
        }

        clearSelection();
        await Promise.all([loadDirectory(), updateQuota()]);
    } catch (err) {
        console.error('Failed to delete path:', err);
        await showModal({
            title: 'Delete Failed',
            message: `Failed to delete "${pathLabel}": ${err.message}`
        });
    }
}