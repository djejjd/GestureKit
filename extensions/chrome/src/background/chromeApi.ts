export type ChromeApi = {
  tabs: {
    query(queryInfo: chrome.tabs.QueryInfo): Promise<chrome.tabs.Tab[]>;
    create(createProperties: chrome.tabs.CreateProperties): Promise<chrome.tabs.Tab>;
    update(tabId: number, updateProperties: chrome.tabs.UpdateProperties): Promise<chrome.tabs.Tab>;
    remove(tabIds: number | number[]): Promise<void>;
  };
};

export const chromeApi: ChromeApi = {
  tabs: chrome.tabs
};
