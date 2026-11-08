import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:stockflow/core/app_bloc_observer.dart';
import 'package:stockflow/core/connectivity/cubit/connectivity_cubit.dart';
import 'package:stockflow/core/env/supabase_config.dart';
import 'package:stockflow/core/service_locator.dart';
import 'package:stockflow/core/sync/cubit/pending_sync_cubit.dart';
import 'package:stockflow/core/sync/cubit/sync_cubit.dart';
import 'package:stockflow/core/theme/app_theme.dart';
import 'package:stockflow/features/transactions/presentation/screens/transactions_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0));

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured) {
    throw StateError(
      'Supabase is not configured. Run with '
      '--dart-define-from-file=env.json (see env.example.json).',
    );
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  // TODO(auth): temporary anonymous sign-in until email/password auth
  // lands. Anonymous auth must be enabled in the Supabase dashboard
  // (Authentication -> Providers -> Anonymous Sign-Ins).
  if (Supabase.instance.client.auth.currentUser == null) {
    await Supabase.instance.client.auth.signInAnonymously();
  }

  final currentUser = Supabase.instance.client.auth.currentUser;
  assert(currentUser != null, 'Supabase sign-in did not produce a user.');
  _logger.i('Supabase auth ready — currentUser.id: ${currentUser?.id}');

  Bloc.observer = AppBlocObserver();
  setupServiceLocator();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // App-wide singletons live ABOVE MaterialApp so pushed routes and modal
    // sheets -- which mount under the Navigator, as siblings of `home` -- can
    // still read them. .value (not create): getIt owns these for the app's
    // lifetime, so BlocProvider must not close them. Screen-scoped blocs
    // (TransactionsBloc, CategoryTotalsCubit) are provided by their own
    // screens instead.
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: getIt<ConnectivityCubit>()),
        BlocProvider.value(value: getIt<PendingSyncCubit>()),
        BlocProvider.value(value: getIt<SyncCubit>()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar')],
        debugShowCheckedModeBanner: false,
        title: 'Daftar',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const TransactionsScreen(),
      ),
    );
  }
}
