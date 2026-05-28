import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/download_manager_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/chat_tab.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum HomeTab {
  receive(Icons.wifi),
  downloads(Icons.download),
  send(Icons.send),
  chat(Icons.chat),
  settings(Icons.settings);

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.receive:
        return t.receiveTab.title;
      case HomeTab.downloads:
        return 'Downloads';
      case HomeTab.send:
        return t.sendTab.title;
      case HomeTab.chat:
        return 'Chat';
      case HomeTab.settings:
        return t.settingsTab.title;
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({required this.initialTab, required this.appStart, super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena {
  bool _dragAndDropIndicator = false;
  HomeTab? _presentedTab;

  @override
  void initState() {
    super.initState();

    ensureRef((ref) async {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);
    final chatOwnsDesktopDrop = !kIsWeb && checkPlatformIsDesktop();

    if (vm.currentTab != HomeTab.chat && _presentedTab != vm.currentTab) {
      _presentRequestedTab(vm.currentTab);
    }

    return DropTarget(
      enable: !chatOwnsDesktopDrop,
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        if (event.files.length == 1 && Directory(event.files.first.path).existsSync()) {
          // user dropped a directory
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(event.files.first.path));
        } else {
          // user dropped one or more files
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(
                  files: event.files,
                  converter: CrossFileConverters.convertXFile,
                ),
              );
        }
        vm.changeTab(HomeTab.send);
      },
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: ChatTab(
                shellDestinations: HomeTab.values
                    .where((tab) => tab != HomeTab.chat)
                    .map(
                      (tab) => ChatShellDestination(
                        icon: tab.icon,
                        label: tab.label,
                        onSelected: () => vm.changeTab(tab),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            if (_dragAndDropIndicator)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.file_download, size: 128),
                    const SizedBox(height: 30),
                    Text(
                      t.sendTab.placeItems,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _presentRequestedTab(HomeTab tab) {
    _presentedTab = tab;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await context.push(() => _HomeTabPage(tab: tab));
      if (!mounted) {
        return;
      }
      _presentedTab = null;
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.chat));
    });
  }
}

class _HomeTabPage extends StatelessWidget {
  final HomeTab tab;

  const _HomeTabPage({required this.tab});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tab.label)),
      body: SafeArea(
        child: switch (tab) {
          HomeTab.receive => const ReceiveTab(),
          HomeTab.downloads => const DownloadManagerPage(),
          HomeTab.send => const SendTab(),
          HomeTab.chat => const ChatTab(),
          HomeTab.settings => const SettingsTab(),
        },
      ),
    );
  }
}
