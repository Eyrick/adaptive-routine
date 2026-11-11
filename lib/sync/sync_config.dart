/// Endereço e chave pública do projeto Supabase. Vêm do arquivo `env.json`
/// (veja docs/SYNC.md), passado com `--dart-define-from-file=env.json`.
/// Sem eles o app funciona normalmente, só que sem sincronizar.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool get syncConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
