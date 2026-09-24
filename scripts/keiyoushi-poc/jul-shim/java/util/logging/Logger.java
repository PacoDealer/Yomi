package java.util.logging;

import java.util.concurrent.ConcurrentHashMap;

/** Yomi stand-in for java.logging: WARNING and above go to stderr, everything else is dropped. */
public class Logger {
    private static final ConcurrentHashMap<String, Logger> LOGGERS = new ConcurrentHashMap<>();
    private final String name;
    private volatile Level level = Level.WARNING;

    protected Logger(String name, String resourceBundleName) { this.name = name; }

    public static Logger getLogger(String name) { return LOGGERS.computeIfAbsent(name, n -> new Logger(n, null)); }
    public static Logger getAnonymousLogger() { return new Logger(null, null); }

    public String getName() { return name; }
    public Level getLevel() { return level; }
    public void setLevel(Level newLevel) { level = newLevel == null ? Level.WARNING : newLevel; }
    public boolean isLoggable(Level l) { return l.intValue() >= level.intValue() && level != Level.OFF; }

    public void log(Level l, String msg) { log(l, msg, null); }
    public void log(Level l, String msg, Throwable thrown) {
        if (!isLoggable(l)) return;
        System.err.println("[" + l + "] " + name + ": " + msg);
        if (thrown != null) thrown.printStackTrace();
    }
    public void severe(String msg) { log(Level.SEVERE, msg); }
    public void warning(String msg) { log(Level.WARNING, msg); }
    public void info(String msg) { log(Level.INFO, msg); }
    public void fine(String msg) { log(Level.FINE, msg); }
}
