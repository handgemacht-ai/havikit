package ai.handgemacht.havikit

/**
 * Pure derivation of a display screen name from a controller/route type name, used
 * by the capture layer's best-effort auto-detection when the host set no screen
 * (wire spec §6.3 precedence). The iOS set covers UIKit generic containers; the
 * Android equivalent adds the framework host classes that carry no screen-specific
 * name. Module prefix and generic arguments are stripped.
 */
public object HaviScreenName {
    private val genericControllers =
        setOf(
            // iOS parity
            "UIViewController",
            "UIHostingController",
            "UINavigationController",
            "UITabBarController",
            "UISplitViewController",
            "UIPageViewController",
            // Android hosts that carry no screen-specific name
            "ComponentActivity",
            "AppCompatActivity",
            "FragmentActivity",
            "NavHostFragment",
        )

    /**
     * The screen name for a fully-qualified type name (`com.app.ReaderActivity`,
     * `UIHostingController<AnyView>`), or null when it is a generic container that
     * carries no useful name.
     */
    public fun screen(typeName: String): String? {
        val withoutModule = typeName.substringAfterLast('.')
        val base = withoutModule.substringBefore('<')
        val trimmed = base.trim()
        if (trimmed.isEmpty() || trimmed in genericControllers) return null
        return trimmed
    }
}
