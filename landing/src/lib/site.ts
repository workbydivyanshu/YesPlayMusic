const repository = 'qier222/YesPlayMusic';
export const repo = `https://github.com/${repository}`;

const suffixes = {
  mac: '-macos.dmg',
  macIntel: '-macos-x64.dmg',
  winSetup: '-windows-x64-setup.exe',
  winPortable: '-windows-x64-portable.zip',
  linux: '-linux-x64.tar.gz',
};
export type Downloads = Partial<Record<keyof typeof suffixes, string>>;

export async function fetchLatestDownloads(request: typeof fetch = fetch): Promise<Downloads | null> {
  try {
    const response = await request(`https://api.github.com/repos/${repository}/releases/latest`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return null;
    const { assets } = await response.json();
    if (!Array.isArray(assets)) return null;

    const result: Downloads = {};
    for (const key of Object.keys(suffixes) as (keyof Downloads)[]) {
      const asset = assets.find(a =>
        typeof a?.name === 'string' && a.name.startsWith('YesPlayMusic-') &&
        a.name.endsWith(suffixes[key]) && typeof a.browser_download_url === 'string' &&
        a.browser_download_url.startsWith(`${repo}/releases/download/`),
      );
      if (asset) result[key] = asset.browser_download_url;
    }
    return result;
  } catch {
    return null;
  }
}

export const links = {
  repo,
  latestRelease: `${repo}/releases/latest`,
  plugins: `${repo}/blob/main/docs/plugins.md`,
  pluginTopic: 'https://github.com/topics/yesplaymusic-plugin',
  changelog: `${repo}/blob/main/CHANGELOG.md`,
  issues: `${repo}/issues/new/choose`,
};
