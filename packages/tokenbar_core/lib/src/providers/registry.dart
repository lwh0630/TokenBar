import 'api/account_api_providers.dart';
import 'api/atlascloud_provider.dart';
import 'api/coding_plan_providers.dart';
import 'api/cookie_b_providers.dart';
import 'api/deepinfra_provider.dart';
import 'api/deepseek_provider.dart';
import 'api/elevenlabs_provider.dart';
import 'api/fireworks_provider.dart';
import 'api/gateway_providers.dart';
import 'api/huggingface_provider.dart';
import 'api/local_auth_a_providers.dart';
import 'api/moonshot_provider.dart';
import 'api/more_api_providers.dart';
import 'api/quota_api_providers.dart';
import 'api/openai_provider.dart';
import 'api/search_api_providers.dart';
import 'api/venice_provider.dart';
import 'api/vercel_provider.dart';
import 'api/xai_provider.dart';
import 'claude/claude_provider.dart';
import 'codex/codex_provider.dart';
import 'cursor/cursor_provider.dart';
import 'provider.dart';

class ProviderRegistry {
  ProviderRegistry._(this.all);

  static final ProviderRegistry instance = ProviderRegistry._([
    CodexProvider(),
    ClaudeProvider(),
    CursorProvider(),
    OpenAiProvider(),
    DeepSeekProvider(),
    MoonshotProvider(),
    XaiProvider(),
    VeniceProvider(),
    DeepInfraProvider(),
    FireworksProvider(),
    HuggingFaceProvider(),
    ElevenLabsProvider(),
    VercelProvider(),
    AtlasCloudProvider(),
    TavilyProvider(),
    LinkupProvider(),
    LiteLlmProvider(),
    Sub2ApiProvider(),
    BifrostProvider(),
    LlmProxyProvider(),
    ClawRouterProvider(),
    AixyProvider(),
    ZaiProvider(),
    OpenRouterProvider(),
    WarpProvider(),
    SyntheticProvider(),
    ChutesProvider(),
    NeuralwattProvider(),
    ZenMuxProvider(),
    ExaProvider(),
    FalProvider(),
    SonioxProvider(),
    PoeProvider(),
    AerostackProvider(),
    CosmicProvider(),
    FloraProvider(),
    FutureAgiProvider(),
    GitKrakenProvider(),
    SailResearchProvider(),
    MunitoProvider(),
    SofyaProvider(),
    ChatboxProvider(),
    IbmBobProvider(),
    KimiProvider(),
    MiniMaxProvider(),
    V0Provider(),
    DevPassProvider(),
    XKiroProvider(),
    AiAndProvider(),
    GroqProvider(),
    MiMoProvider(),
    CopilotProvider(),
  ]);

  final List<UsageProvider> all;

  UsageProvider? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
