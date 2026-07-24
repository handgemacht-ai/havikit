import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useState } from 'react';
import { SafeAreaView, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import {
  HaviOverlay,
  capture,
  getAuthState,
  getIsEnabled,
  isAvailable,
  log,
  logNetworkError,
  setContext,
  setScreen,
  setTag,
  signOut,
  start,
  type HaviAuthState,
} from '@handgemacht-ai/expo-havikit';

const SCREENS = ['Home', 'Detail', 'Profile'] as const;

function describeAuth(state: HaviAuthState | null): string {
  if (!state) return 'loading…';
  switch (state.status) {
    case 'authenticated':
      return `authenticated (${state.workspaceId})`;
    case 'needsReconnect':
      return 'needsReconnect';
    default:
      return 'unconfigured';
  }
}

export default function App() {
  const [status, setStatus] = useState('starting HaviKit…');
  const [authState, setAuthState] = useState<HaviAuthState | null>(null);
  const [enabled, setEnabled] = useState(false);
  const [screenIndex, setScreenIndex] = useState(0);

  const refresh = useCallback(async () => {
    setEnabled(getIsEnabled());
    setAuthState(await getAuthState());
  }, []);

  useEffect(() => {
    start({ enabled: true, baseUrl: 'https://havi.handgemacht.ai', project: 'expo-example' })
      .then(async () => {
        setStatus('HaviKit started');
        setScreen(SCREENS[0]);
        await refresh();
      })
      .catch((error: unknown) => setStatus(`start() rejected: ${String(error)}`));
  }, [refresh]);

  const run = (label: string, action: () => void) => () => {
    action();
    setStatus(label);
  };

  const cycleScreen = () => {
    const next = (screenIndex + 1) % SCREENS.length;
    setScreenIndex(next);
    setScreen(SCREENS[next]);
    setStatus(`setScreen('${SCREENS[next]}')`);
  };

  return (
    <View style={styles.root}>
      <SafeAreaView style={styles.safe}>
        <ScrollView contentContainerStyle={styles.content}>
          <Text style={styles.title}>HaviKit dogfood</Text>

          <View style={styles.card}>
            <Row label="isAvailable" value={String(isAvailable)} />
            <Row label="getIsEnabled()" value={String(enabled)} />
            <Row label="auth state" value={describeAuth(authState)} />
            <Row label="screen" value={SCREENS[screenIndex]} />
            <Row label="last action" value={status} />
          </View>

          <Button title="Capture feedback" onPress={run(`capture('${SCREENS[screenIndex]}')`, () => capture(SCREENS[screenIndex]))} />
          <Button title="Send test log" onPress={run('log()', () => log('Example test log', 'info', 'example'))} />
          <Button
            title="Send test network error"
            onPress={run('logNetworkError()', () =>
              logNetworkError('GET https://havi.handgemacht.ai/health 500 Internal Server Error')
            )}
          />
          <Button title="Cycle screen name" onPress={cycleScreen} />
          <Button
            title="Set context + tag"
            onPress={run('setContext() + setTag()', () => {
              setContext('example', { build: 'debug', tester: 'dogfood' });
              setTag('surface', 'expo-example');
            })}
          />
          <Button title="Refresh auth state" onPress={() => void refresh()} />
          <Button title="Sign out" onPress={run('signOut()', () => { signOut(); void refresh(); })} />
        </ScrollView>
      </SafeAreaView>

      <HaviOverlay style={StyleSheet.absoluteFill} pointerEvents="box-none" />
      <StatusBar style="auto" />
    </View>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={styles.rowValue}>{value}</Text>
    </View>
  );
}

function Button({ title, onPress }: { title: string; onPress: () => void }) {
  return (
    <TouchableOpacity style={styles.button} onPress={onPress} activeOpacity={0.7}>
      <Text style={styles.buttonText}>{title}</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#0f1115' },
  safe: { flex: 1 },
  content: { padding: 20, gap: 12 },
  title: { color: '#fff', fontSize: 24, fontWeight: '700', marginBottom: 4 },
  card: { backgroundColor: '#1b1f27', borderRadius: 12, padding: 16, gap: 8, marginBottom: 8 },
  row: { flexDirection: 'row', justifyContent: 'space-between', gap: 12 },
  rowLabel: { color: '#8b93a7', fontSize: 14 },
  rowValue: { color: '#e6e9f0', fontSize: 14, flexShrink: 1, textAlign: 'right' },
  button: { backgroundColor: '#3b82f6', borderRadius: 10, paddingVertical: 14, alignItems: 'center' },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});
