/**
 * Per-key throttle: runs immediately, then at most once per `intervalMs`, always ending with
 * a trailing run so the last change is never lost.
 */
export class KeyedThrottle {
  private timers = new Map<string, NodeJS.Timeout>();
  private pending = new Map<string, () => unknown>();

  constructor(private readonly intervalMs: number) {}

  run(key: string, fn: () => unknown) {
    if (this.timers.has(key)) {
      this.pending.set(key, fn);
      return;
    }
    void Promise.resolve().then(fn);
    this.arm(key);
  }

  private arm(key: string) {
    const timer = setTimeout(() => {
      this.timers.delete(key);
      const next = this.pending.get(key);
      if (next) {
        this.pending.delete(key);
        this.run(key, next);
      }
    }, this.intervalMs);
    timer.unref?.();
    this.timers.set(key, timer);
  }

  clear() {
    for (const t of this.timers.values()) clearTimeout(t);
    this.timers.clear();
    this.pending.clear();
  }
}
