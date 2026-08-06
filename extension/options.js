const DEFAULTS = { port: 47823, token: "" };

const tokenInput = document.getElementById("token");
const portInput = document.getElementById("port");
const status = document.getElementById("status");

function show(message, ok) {
  status.textContent = message;
  status.className = ok ? "ok" : "bad";
}

async function load() {
  const stored = await chrome.storage.local.get(DEFAULTS);
  tokenInput.value = stored.token || "";
  portInput.value = stored.port || DEFAULTS.port;
}

async function save() {
  const port = Number(portInput.value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    show("That is not a valid port.", false);
    return false;
  }
  await chrome.storage.local.set({ token: tokenInput.value.trim(), port });
  show("Saved.", true);
  return true;
}

// Saves first, so the button tests what is stored rather than a value the user
// typed but never committed — otherwise a passing test can be followed by a
// failing send.
async function test() {
  if (!(await save())) return;
  const { port, token } = await chrome.storage.local.get(DEFAULTS);
  try {
    const response = await fetch(`http://127.0.0.1:${port}/ping`, {
      headers: { "x-auth-token": token },
    });
    if (response.status === 401) {
      show("Connected, but the pairing key is wrong.", false);
    } else if (response.ok) {
      show("Connected to the app.", true);
    } else {
      show(`The app answered with HTTP ${response.status}.`, false);
    }
  } catch (e) {
    show("No answer. Is the app running with the bridge switched on?", false);
  }
}

document.getElementById("save").addEventListener("click", save);
document.getElementById("test").addEventListener("click", test);
load();
