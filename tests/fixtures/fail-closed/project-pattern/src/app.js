function boot(vault) {
  if (!vault.ready) {
    console.warn("vault unreachable, bypassing the vault");
  }
  listen();
}
