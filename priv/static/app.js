let currentOwner = 'alice';
let currentPath = [];
let selectedItem = null;

// Initialize Workspace
document.addEventListener('DOMContentLoaded', () => {
    initWebSocket();
    loadDirectory();
    updateQuota();
});

// Real-time WebSocket Handler
function initWebSocket() {
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(`${protocol}//${location.host}/ws`);

    ws.onopen = () => {
        document.getElementById('wsStatus').innerText = 'Active';
        document.getElementById('wsStatus').className = 'text-emerald-400';
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
        document.getElementById('wsStatus').className = 'text-red-400';
        setTimeout(initWebSocket, 3000);
    };
}

// REST API Operations
async function loadDirectory() {
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
        const tagsStr = item.tags ? item.tags.map(t => `<span class="bg-slate-800 text-emerald-400 px-1.5 py-0.5 rounded text-[10px]">${t}</span>`).join(' ') : '-';

        return `
            <div onclick="selectRow(this, '${item.name}')" 
                 ondblclick="handleDblClick('${item.name}', '${item.type}')" 
                 class="grid grid-cols-12 gap-2 p-2 hover:bg-slate-900 rounded cursor-pointer border border-transparent hover:border-slate-800 text-slate-300 items-center">
                <div class="col-span-5 flex items-center gap-2 font-semibold">
                    <span>${icon}</span>
                    <span class="truncate">${item.name}</span>
                </div>
                <div class="col-span-2 text-slate-500">${item.type}</div>
                <div class="col-span-2 text-slate-400">${sizeStr}</div>
                <div class="col-span-3 flex gap-1 overflow-x-auto">${tagsStr}</div>
            </div>
        `;
    }).join('');
}

function renderBreadcrumb() {
    const el = document.getElementById('breadcrumb');
    let html = `<span onclick="navigateTo([])" class="text-emerald-400 font-bold cursor-pointer hover:underline">/${currentOwner}</span>`;
    
    let accPath = [];
    currentPath.forEach(part => {
        accPath.push(part);
        const pathTarget = [...accPath];
        html += `<span class="text-slate-600">/</span><span onclick="navigateTo(['${pathTarget.join("','")}'])" class="cursor-pointer hover:underline text-slate-300">${part}</span>`;
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
    const name = prompt('Enter folder name:');
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
    const name = prompt('Enter file name (e.g. notes.txt):');
    if (!name) return;
    const content = prompt('Enter file content:', 'Sample text');
    const tagsInput = prompt('Enter tags comma separated:', 'fp,urgent');
    const tags = tagsInput ? tagsInput.split(',').map(t => t.trim()) : [];

    const pathArr = [...currentPath, name];
    await fetch(`/api/file/${currentOwner}/${pathArr.join('/')}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            type: 'file',
            content: content || '',
            tags: tags,
            mime_type: 'text/plain'
        })
    });
    loadDirectory();
}

async function viewFileContent(filename) {
    const pathArr = [...currentPath, filename];
    const res = await fetch(`/api/file/${currentOwner}/${pathArr.join('/')}`);
    const data = await res.json();
    if (data.status === 'ok') {
        alert(`📄 File: ${filename}\n\nContent:\n${data.data.content}\n\nTags: ${data.data.tags ? data.data.tags.join(', ') : 'None'}`);
    }
}

async function searchTag() {
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

        container.innerHTML = data.matches.map(item => `
            <div class="grid grid-cols-12 gap-2 p-2 bg-slate-900/80 rounded border border-emerald-900/50 text-slate-300 items-center">
                <div class="col-span-5 flex items-center gap-2 font-mono text-emerald-400 font-bold">
                    <span>📄</span>
                    <span>${item.path.join('/')}</span>
                </div>
                <div class="col-span-4 text-slate-500 font-mono">Matched via ETS Index</div>
                <div class="col-span-3 font-mono text-xs text-emerald-300">Tag: ${tag}</div>
            </div>
        `).join('');
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
                <div class="font-bold border-b border-slate-800 pb-1 mb-1 text-slate-400">ETS Table: kvfs_user_quota</div>
                <pre class="text-[10px]">${JSON.stringify(q, null, 2)}</pre>
            `;
        }
        
        // Fetch All Tag Indexes for Monitor
        const tagRes = await fetch(`/api/search/tag?tag=fp`);
        const tagData = await tagRes.json();
        document.getElementById('etsTagIndexView').innerHTML = `
            <div class="font-bold border-b border-slate-800 pb-1 mb-1 text-slate-400">ETS Table: kvfs_tag_index (Sample Tag: 'fp')</div>
            <pre class="text-[10px]">${JSON.stringify(tagData, null, 2)}</pre>
        `;
    } catch (err) {
        console.error('Quota update error:', err);
    }
}

function selectRow(element, name) {
    document.querySelectorAll('#fileList > div').forEach(el => el.classList.remove('bg-slate-800', 'border-slate-700'));
    element.classList.add('bg-slate-800', 'border-slate-700');
    selectedItem = name;
}