// Mimics how an iOS host starts the bridge: EmbeddedBridge.start on a loopback port, no main().
public class Launcher {
    public static void main(String[] a) throws Exception {
        long t0 = System.nanoTime();
        int port = mextensionserver.EmbeddedBridge.start(Integer.parseInt(a[0]), a[1]);
        System.out.println("BRIDGE_READY port=" + port + " startMs=" + (System.nanoTime() - t0) / 1_000_000);
        Thread.currentThread().join();
    }
}
