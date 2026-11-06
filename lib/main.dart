import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Use the anon (public) key only. Never put the service_role key in the app.
const supabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://rvqrvcznevgqiyrpijyj.supabase.co');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_UnzwelpS6TBund2L95qdOQ_Bi6otmF2');

const green = Color(0xFF2EE58A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const BayverApp());
}

SupabaseClient get db => Supabase.instance.client;

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class BayverApp extends StatelessWidget {
  const BayverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bayver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: const ColorScheme.dark(primary: green),
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
      ),
      home: StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (context, _) =>
            db.auth.currentSession == null ? const AuthScreen() : const HomeShell(),
      ),
    );
  }
}

// ---------- Auth ----------

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final username = TextEditingController();
  bool signUp = false;
  bool busy = false;

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      if (signUp) {
        await db.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          data: {'username': username.text.trim()},
        );
      } else {
        await db.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Something went wrong: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Text('BAYVER',
                  style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold, color: green)),
              const SizedBox(height: 24),
              if (signUp)
                TextField(
                  controller: username,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(signUp ? 'Create account' : 'Log in'),
              ),
              TextButton(
                onPressed: () => setState(() => signUp = !signUp),
                child: Text(signUp
                    ? 'Already have an account? Log in'
                    : 'New here? Create an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Shell ----------

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    const tabs = [PlayTab(), PassportTab(), WalletTab()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: tabs)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sports_esports), label: 'Play'),
          NavigationDestination(icon: Icon(Icons.badge), label: 'Passport'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
        ],
      ),
    );
  }
}

// ---------- Play: tournaments ----------

class PlayTab extends StatefulWidget {
  const PlayTab({super.key});

  @override
  State<PlayTab> createState() => _PlayTabState();
}

class _PlayTabState extends State<PlayTab> {
  List<Map<String, dynamic>> tournaments = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await db
          .from('tournaments')
          .select('id, name, status, max_players, tournament_players(count)')
          .order('created_at', ascending: false);
      if (mounted) setState(() => tournaments = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (mounted) toast(context, 'Could not load tournaments: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New tournament'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name, e.g. MMU Open'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await db.from('tournaments').insert({'name': name, 'host_id': db.auth.currentUser!.id});
      await load();
    } catch (e) {
      if (mounted) toast(context, 'Could not create: $e');
    }
  }

  Future<void> join(String id) async {
    try {
      await db.from('tournament_players').insert({
        'tournament_id': id,
        'player_id': db.auth.currentUser!.id,
      });
      if (mounted) toast(context, 'You are in!');
      await load();
    } on PostgrestException catch (e) {
      if (mounted) {
        toast(context, e.code == '23505' ? 'You already joined this one' : e.message);
      }
    }
  }

  int playerCount(Map<String, dynamic> t) {
    final list = t['tournament_players'] as List?;
    if (list == null || list.isEmpty) return 0;
    return (list.first['count'] as int?) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Tournaments'),
        backgroundColor: Colors.transparent,
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: create,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : tournaments.isEmpty
              ? const Center(child: Text('No tournaments yet. Create the first one.'))
              : ListView.builder(
                  itemCount: tournaments.length,
                  itemBuilder: (context, i) {
                    final t = tournaments[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        title: Text(t['name']),
                        subtitle: Text(
                            '${playerCount(t)}/${t['max_players']} players · ${t['status']}'),
                        trailing: FilledButton(
                          onPressed: () => join(t['id']),
                          child: const Text('Join'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ---------- Passport: profile ----------

class PassportTab extends StatefulWidget {
  const PassportTab({super.key});

  @override
  State<PassportTab> createState() => _PassportTabState();
}

class _PassportTabState extends State<PassportTab> {
  final displayName = TextEditingController();
  final efootballId = TextEditingController();
  String username = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final row =
          await db.from('profiles').select().eq('id', db.auth.currentUser!.id).single();
      if (!mounted) return;
      setState(() {
        username = row['username'] ?? '';
        displayName.text = row['display_name'] ?? '';
        efootballId.text = row['efootball_id'] ?? '';
      });
    } catch (e) {
      if (mounted) toast(context, 'Could not load passport: $e');
    }
  }

  Future<void> save() async {
    try {
      await db.from('profiles').update({
        'display_name': displayName.text.trim(),
        'efootball_id': efootballId.text.trim(),
      }).eq('id', db.auth.currentUser!.id);
      if (mounted) toast(context, 'Passport saved');
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('@$username',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: displayName,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        TextField(
          controller: efootballId,
          decoration: const InputDecoration(labelText: 'eFootball ID'),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: save, child: const Text('Save passport')),
        TextButton(onPressed: () => db.auth.signOut(), child: const Text('Log out')),
      ],
    );
  }
}

// ---------- Wallet: Bay Coins ----------

class WalletTab extends StatefulWidget {
  const WalletTab({super.key});

  @override
  State<WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<WalletTab> {
  List<Map<String, dynamic>> entries = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await db
          .from('coin_ledger')
          .select('amount, reason, created_at')
          .order('created_at', ascending: false);
      if (mounted) setState(() => entries = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (mounted) toast(context, 'Could not load wallet: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = entries.fold<int>(0, (sum, e) => sum + (e['amount'] as int));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('BAY COINS', style: TextStyle(color: Colors.white54)),
        Text('$balance',
            style: const TextStyle(
                fontSize: 56, fontWeight: FontWeight.bold, color: Colors.amber)),
        const Text('Earned by playing. Cannot be bought or cashed out.',
            style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 24),
        const Text('Activity', style: TextStyle(fontWeight: FontWeight.bold)),
        ...entries.map((e) => ListTile(
              title: Text(e['reason']),
              trailing: Text(
                '${e['amount'] >= 0 ? '+' : ''}${e['amount']}',
                style: TextStyle(color: e['amount'] >= 0 ? green : Colors.orange),
              ),
            )),
        TextButton(onPressed: load, child: const Text('Refresh')),
      ],
    );
  }
}