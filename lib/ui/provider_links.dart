import 'package:tokenbar_core/tokenbar_core.dart';

/// Whether the card links to an official project for a self-hosted service.
bool providerLinkIsProject(String providerId) => _projectUrls.containsKey(providerId);

/// Returns the provider's account overview, console, or official project.
Uri? providerOfficialUrl(UsageSnapshot snapshot, {AccountConfig? account}) {
  final id = snapshot.providerId;
  final url = _providerUrls[id] ?? _projectUrls[id];
  if (url == null) return null;

  final regionalUrls = _regionalUrls[id];
  if (regionalUrls == null) return Uri.parse(url);

  final String? region;
  if (account != null && account.id == snapshot.accountId && account.providerId == id) {
    region = FieldValues.of(ProviderRegistry.instance.byId(id)!, account)['region'];
  } else {
    // A synced balance can identify the region even without account settings.
    final currency = snapshot.credits.firstOrNull?.currency;
    region = switch ((id, currency)) {
      ('moonshot', 'USD') => 'international',
      ('siliconflow', 'CNY') => 'cn',
      _ => null,
    };
  }
  return Uri.parse(regionalUrls[region] ?? url);
}

// Keep the browser URLs independent of the provider's API host and credentials.
const _providerUrls = {
  'abliteration': 'https://abliteration.ai/console',
  'aerostack': 'https://app.aerostack.dev/',
  'aiand': 'https://console.aiand.com',
  'aixy': 'https://dash.aixy-gateway.com',
  'atlascloud': 'https://www.atlascloud.ai/console',
  'chatbox': 'https://chatboxai.app/user',
  'chutes': 'https://chutes.ai/app/settings',
  'claude': 'https://claude.ai/settings/usage',
  'clawrouter': 'https://clawrouter.openclaw.ai/dashboard/home',
  'codex': 'https://chatgpt.com/settings/usage',
  'copilot': 'https://github.com/settings/copilot',
  'cosmic': 'https://app.cosmicjs.com/',
  'cursor': 'https://cursor.com/dashboard',
  'deepinfra': 'https://deepinfra.com/dash',
  'deepseek': 'https://platform.deepseek.com/usage',
  'devpass': 'https://devpass.llmgateway.io/dashboard',
  'elevenlabs': 'https://elevenlabs.io/app/usage',
  'exa': 'https://dashboard.exa.ai/',
  'fal': 'https://fal.ai/dashboard',
  'fireworks': 'https://app.fireworks.ai/account/home',
  'flora': 'https://app.flora.ai',
  'futureagi': 'https://app.futureagi.com/',
  'gemini': 'https://gemini.google.com/usage',
  'gitkraken': 'https://gitkraken.dev/login',
  'groq': 'https://console.groq.com/dashboard',
  'huggingface': 'https://huggingface.co/settings/account',
  'ibmbob': 'https://bob.ibm.com/login',
  'kimi': 'https://www.kimi.com/code/console',
  'linkup': 'https://app.linkup.so/',
  'mimo': 'https://platform.xiaomimimo.com/#/console/usage',
  'minimax': 'https://platform.minimax.cn/console/home',
  'moonshot': 'https://platform.kimi.com/console/account',
  'munito': 'https://console.munito.ai',
  'neuralwatt': 'https://portal.neuralwatt.com/dashboard',
  'openai': 'https://platform.openai.com/settings/organization/analytics/usage',
  'openrouter': 'https://openrouter.ai/activity',
  'poe': 'https://poe.com/settings',
  'sailresearch': 'https://app.sailresearch.com',
  'siliconflow': 'https://cloud.siliconflow.com/console',
  'sofya': 'https://sofya.co/dashboard',
  'soniox': 'https://console.soniox.com/',
  'synthetic': 'https://synthetic.new/users/login',
  'tavily': 'https://app.tavily.com/home',
  'tripo': 'https://developers.tripo3d.ai/zh/usage',
  'trustedrouter': 'https://trustedrouter.com/console/api-keys',
  'v0': 'https://v0.app/settings',
  'venice': 'https://venice.ai/settings/api',
  'vercel': 'https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai-gateway&title=Go+to+AI+Gateway',
  'warp': 'https://app.warp.dev/login',
  'xai': 'https://console.x.ai/',
  'xkiro': 'https://xkiro.com/dashboard',
  'zai': 'https://bigmodel.cn/console/overview',
  'zenmux': 'https://zenmux.ai/platform/management',
};

const _regionalUrls = {
  'kimi': {'international': 'https://www.kimi.ai/code/console'},
  'minimax': {'global': 'https://platform.minimax.io/console/home'},
  'moonshot': {'international': 'https://platform.kimi.ai/console/account'},
  'siliconflow': {'cn': 'https://cloud.siliconflow.cn/'},
  'zai': {'global': 'https://z.ai/manage-apikey/apikey-list'},
};

const _projectUrls = {
  'bifrost': 'https://github.com/maximhq/bifrost',
  'litellm': 'https://github.com/BerriAI/litellm',
  'llmproxy': 'https://github.com/Mirrowel/LLM-API-Key-Proxy',
  'sub2api': 'https://github.com/Wei-Shaw/sub2api',
};
