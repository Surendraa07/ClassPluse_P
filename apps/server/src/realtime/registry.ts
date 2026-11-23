/**
 * Lets REST handlers notify the realtime layer without importing Socket.io directly
 * (and without a cycle). When no realtime server is attached (e.g. REST-only tests) calls are no-ops.
 */
export interface RealtimeNotifier {
  participantJoined(sessionId: string): void;
}

let current: RealtimeNotifier | null = null;

export function setRealtime(notifier: RealtimeNotifier | null) {
  current = notifier;
}

export function realtime(): RealtimeNotifier | null {
  return current;
}
