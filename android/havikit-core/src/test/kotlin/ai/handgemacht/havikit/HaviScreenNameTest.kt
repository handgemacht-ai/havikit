package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** Screen-name derivation (wire spec §6.3): strip module + generics, drop generic containers. */
class HaviScreenNameTest {
    @Test
    fun stripsModulePrefixAndGenericArgs() {
        assertEquals("ReaderViewController", HaviScreenName.screen("MyApp.ReaderViewController"))
        assertEquals("ReaderActivity", HaviScreenName.screen("com.app.ReaderActivity"))
        assertEquals("ReaderScreen", HaviScreenName.screen("ReaderScreen<AnyView>"))
    }

    @Test
    fun genericContainersResolveToNull() {
        assertNull(HaviScreenName.screen("UIHostingController<AnyView>"))
        assertNull(HaviScreenName.screen("UINavigationController"))
        assertNull(HaviScreenName.screen("androidx.activity.ComponentActivity"))
        assertNull(HaviScreenName.screen("androidx.navigation.fragment.NavHostFragment"))
        assertNull(HaviScreenName.screen(""))
    }
}
