# Link Hit-Test Spike

Goal: validate the extension-side last pointer strategy for ordinary links.

Manual checks:

1. Load `pages/basic-links.html` in Chrome.
2. Move the pointer over each link.
3. Trigger a simulated gesture event from the background script.
4. Confirm `http:` and `https:` links are accepted.
5. Confirm `javascript:` links are rejected.
6. Load `pages/no-link.html` and confirm no action runs.
