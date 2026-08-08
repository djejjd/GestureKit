export type ChromeApi = {
  tabs: {
    query(queryInfo: chrome.tabs.QueryInfo): Promise<chrome.tabs.Tab[]>;
    create(createProperties: chrome.tabs.CreateProperties): Promise<chrome.tabs.Tab>;
    update(tabId: number, updateProperties: chrome.tabs.UpdateProperties): Promise<chrome.tabs.Tab>;
    remove(tabIds: number | number[]): Promise<void>;
    goBack(tabId: number): Promise<void>;
    goForward(tabId: number): Promise<void>;
    reload(tabId?: number, reloadProperties?: chrome.tabs.ReloadProperties): Promise<void>;
    sendMessage(tabId: number, message: unknown): Promise<unknown>;
  };
  sessions: {
    restore(sessionId?: string): Promise<chrome.sessions.Session>;
  };
};

export const chromeApi: ChromeApi = {
  tabs: chrome.tabs,
  sessions: chrome.sessions
};
