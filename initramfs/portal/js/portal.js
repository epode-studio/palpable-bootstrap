/**
 * Palpable Captive Portal JavaScript
 */

const API_BASE = '/api';

// Detect test mode (static file server)
const IS_TEST_MODE = window.location.port === '3333' || window.location.hostname === 'localhost';

// State
let currentStep = 1;
let selectedNetwork = null;
let deviceInfo = null;

// DOM Elements
const steps = document.querySelectorAll('.step');
const stepContents = {
    wifi: document.getElementById('step-wifi'),
    claim: document.getElementById('step-claim'),
    complete: document.getElementById('step-complete')
};

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
    await loadDeviceInfo();
    await scanNetworks();
    setupEventListeners();
});

// Load device information
async function loadDeviceInfo() {
    try {
        const response = await fetch(`${API_BASE}/device-info.json`);
        deviceInfo = await response.json();
        console.log('Device info:', deviceInfo);
    } catch (error) {
        console.error('Failed to load device info:', error);
        deviceInfo = {
            deviceId: 'unknown',
            deviceName: 'palpable',
            version: '1.0.0'
        };
    }
}

// Scan for available WiFi networks
async function scanNetworks() {
    const networkList = document.getElementById('network-list');

    try {
        // Try CGI endpoint first, fall back to static JSON for testing
        let response = await fetch(`${API_BASE}/scan-wifi`);
        if (!response.ok || response.headers.get('content-type')?.includes('text/html')) {
            response = await fetch(`${API_BASE}/scan-wifi.json`);
        }
        const networks = await response.json();

        if (networks.length === 0) {
            networkList.innerHTML = `
                <div class="loading">
                    <span>No networks found. Click below to enter manually.</span>
                </div>
            `;
            return;
        }

        networkList.innerHTML = networks.map(network => `
            <div class="network-item" data-ssid="${escapeHtml(network.ssid)}">
                <svg class="network-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M5 12.55a11 11 0 0114 0"/>
                    <path d="M1.42 9a16 16 0 0121.16 0"/>
                    <path d="M8.53 16.11a6 6 0 016.95 0"/>
                    <circle cx="12" cy="20" r="1"/>
                </svg>
                <span class="network-name">${escapeHtml(network.ssid)}</span>
                ${renderSignalStrength(network.signal)}
            </div>
        `).join('');

        // Add click handlers
        networkList.querySelectorAll('.network-item').forEach(item => {
            item.addEventListener('click', () => selectNetwork(item));
        });

    } catch (error) {
        console.error('Failed to scan networks:', error);
        networkList.innerHTML = `
            <div class="loading">
                <span>Could not scan networks. Enter manually below.</span>
            </div>
        `;
    }
}

// Render signal strength bars
function renderSignalStrength(signal) {
    const bars = 4;
    const activeBars = Math.ceil((signal / 100) * bars);

    return `
        <div class="network-signal">
            ${Array.from({ length: bars }, (_, i) =>
                `<div class="signal-bar ${i < activeBars ? 'active' : ''}"></div>`
            ).join('')}
        </div>
    `;
}

// Select a network from the list
function selectNetwork(item) {
    // Deselect previous
    document.querySelectorAll('.network-item').forEach(el => el.classList.remove('selected'));

    // Select new
    item.classList.add('selected');
    selectedNetwork = item.dataset.ssid;

    // Show password form
    const form = document.getElementById('wifi-form');
    const ssidInput = document.getElementById('ssid');

    form.classList.remove('hidden');
    ssidInput.value = selectedNetwork;
    document.getElementById('password').focus();
}

// Setup event listeners
function setupEventListeners() {
    // Manual WiFi entry
    document.getElementById('btn-manual-wifi').addEventListener('click', () => {
        const form = document.getElementById('wifi-form');
        form.classList.remove('hidden');
        document.getElementById('ssid').focus();
    });

    // WiFi form submission
    document.getElementById('wifi-form').addEventListener('submit', handleWifiSubmit);

    // Password toggle
    document.querySelector('.toggle-password').addEventListener('click', (e) => {
        const input = document.getElementById('password');
        const isPassword = input.type === 'password';
        input.type = isPassword ? 'text' : 'password';
    });

    // Claim options
    document.getElementById('claim-code').addEventListener('click', () => {
        document.querySelectorAll('.claim-option').forEach(el => el.classList.remove('selected'));
        document.getElementById('claim-code').classList.add('selected');
        document.getElementById('code-form').classList.remove('hidden');
        document.getElementById('qr-display').classList.add('hidden');
        document.getElementById('claim-code-input').focus();
    });

    document.getElementById('claim-qr').addEventListener('click', () => {
        document.querySelectorAll('.claim-option').forEach(el => el.classList.remove('selected'));
        document.getElementById('claim-qr').classList.add('selected');
        document.getElementById('code-form').classList.add('hidden');
        document.getElementById('qr-display').classList.remove('hidden');
        generateQRCode();
    });

    // Claim code form
    document.getElementById('code-form').addEventListener('submit', handleClaimSubmit);

    // Auto-format code input
    document.getElementById('claim-code-input').addEventListener('input', (e) => {
        e.target.value = e.target.value.replace(/\D/g, '').slice(0, 6);
    });

    // Skip claim
    document.getElementById('btn-skip-claim').addEventListener('click', () => {
        goToStep(3);
        startCountdown();
    });
}

// Handle WiFi form submission
async function handleWifiSubmit(e) {
    e.preventDefault();

    const form = e.target;
    const btn = form.querySelector('button[type="submit"]');
    const btnText = btn.querySelector('span');
    const btnSpinner = btn.querySelector('.btn-spinner');

    // Show loading state
    btn.disabled = true;
    btnText.textContent = 'Connecting...';
    btnSpinner.classList.remove('hidden');

    const ssid = document.getElementById('ssid').value;
    const password = document.getElementById('password').value;

    try {
        let result;

        if (IS_TEST_MODE) {
            // Simulate connection delay in test mode
            await new Promise(resolve => setTimeout(resolve, 1500));
            result = { success: true, ip: '192.168.1.100' };
            console.log('TEST MODE: Simulating WiFi connection to', ssid);
        } else {
            const response = await fetch(`${API_BASE}/connect-wifi`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ ssid, password })
            });
            result = await response.json();
        }

        if (result.success) {
            selectedNetwork = ssid;
            goToStep(2);
        } else {
            alert('Failed to connect: ' + (result.error || 'Unknown error'));
        }
    } catch (error) {
        console.error('WiFi connection error:', error);
        alert('Connection failed. Please try again.');
    } finally {
        btn.disabled = false;
        btnText.textContent = 'Connect';
        btnSpinner.classList.add('hidden');
    }
}

// Handle claim code submission
async function handleClaimSubmit(e) {
    e.preventDefault();

    const form = e.target;
    const btn = form.querySelector('button[type="submit"]');
    const btnText = btn.querySelector('span');
    const btnSpinner = btn.querySelector('.btn-spinner');

    const code = document.getElementById('claim-code-input').value;

    if (code.length !== 6) {
        alert('Please enter a 6-digit code');
        return;
    }

    // Show loading state
    btn.disabled = true;
    btnText.textContent = 'Claiming...';
    btnSpinner.classList.remove('hidden');

    try {
        let result;

        if (IS_TEST_MODE) {
            // Simulate claim in test mode
            await new Promise(resolve => setTimeout(resolve, 1000));
            result = { success: true };
            console.log('TEST MODE: Simulating device claim with code', code);
        } else {
            const response = await fetch(`${API_BASE}/claim`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    code,
                    deviceId: deviceInfo.deviceId
                })
            });
            result = await response.json();
        }

        if (result.success) {
            goToStep(3);
            startCountdown();
        } else {
            alert('Failed to claim: ' + (result.error || 'Invalid code'));
        }
    } catch (error) {
        console.error('Claim error:', error);
        alert('Claim failed. Please try again.');
    } finally {
        btn.disabled = false;
        btnText.textContent = 'Claim Device';
        btnSpinner.classList.add('hidden');
    }
}

// Generate QR code for app scanning
function generateQRCode() {
    const qrContainer = document.getElementById('qr-code');
    const claimUrl = `palpable://claim?deviceId=${deviceInfo.deviceId}`;

    // Generate QR code using API service (works offline too with cached response)
    const qrApiUrl = `https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(claimUrl)}&bgcolor=ffffff&color=000000`;

    qrContainer.innerHTML = `
        <img src="${qrApiUrl}" alt="QR Code" style="width: 180px; height: 180px; border-radius: 8px;"
             onerror="this.parentElement.innerHTML='<div style=\\'padding: 40px; text-align: center; font-size: 14px; color: #666;\\'><p style=\\'margin-bottom: 8px;\\'>Device ID:</p><p style=\\'font-family: monospace; font-weight: bold; font-size: 18px;\\'>${deviceInfo.deviceId}</p></div>'" />
    `;
}

// Navigate to a step
function goToStep(stepNum) {
    currentStep = stepNum;

    // Update step indicators
    steps.forEach((step, index) => {
        const num = index + 1;
        step.classList.remove('active', 'completed');

        if (num < stepNum) {
            step.classList.add('completed');
        } else if (num === stepNum) {
            step.classList.add('active');
        }
    });

    // Show/hide content
    Object.keys(stepContents).forEach((key, index) => {
        if (index + 1 === stepNum) {
            stepContents[key].classList.remove('hidden');
        } else {
            stepContents[key].classList.add('hidden');
        }
    });

    // Update complete step info
    if (stepNum === 3) {
        document.getElementById('device-name').textContent = deviceInfo.deviceName;
        document.getElementById('device-id').textContent = deviceInfo.deviceId;
        document.getElementById('wifi-network').textContent = selectedNetwork || 'Not configured';
    }
}

// Start reboot countdown
function startCountdown() {
    let seconds = 10;
    const countdownEl = document.getElementById('countdown');

    const interval = setInterval(() => {
        seconds--;
        countdownEl.textContent = seconds;

        if (seconds <= 0) {
            clearInterval(interval);
            rebootDevice();
        }
    }, 1000);
}

// Trigger device reboot
async function rebootDevice() {
    try {
        await fetch(`${API_BASE}/reboot`, { method: 'POST' });
    } catch (error) {
        // Expected - connection will drop during reboot
        console.log('Rebooting...');
    }
}

// Utility: escape HTML
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
