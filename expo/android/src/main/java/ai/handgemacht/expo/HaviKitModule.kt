package ai.handgemacht.expo

import ai.handgemacht.havikit.Havi
import ai.handgemacht.havikit.HaviAuthState
import ai.handgemacht.havikit.HaviConfig
import ai.handgemacht.havikit.HaviLogLevel
import ai.handgemacht.havikit.HaviPriority
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

/**
 * The JS `start(config)` argument, mapped 1:1 from the `HaviConfig` TS type
 * (which mirrors the stamped `HAVI_*` keys). Optional values arrive as `null`.
 */
internal class HaviStartConfig : Record {
    @Field
    var enabled: Boolean = false

    @Field
    var baseUrl: String = ""

    @Field
    var workspaceId: String? = null

    @Field
    var project: String? = null

    @Field
    var worktree: String? = null

    @Field
    var branch: String? = null

    @Field
    var commit: String? = null

    @Field
    var imageFormat: String? = null

    @Field
    var devToken: String? = null
}

/**
 * Rejects `start` when the SDK is enabled without a usable base URL — the
 * catchable counterpart of `HaviConfig.fromMetaData`'s `IllegalStateException`,
 * so a misconfiguration never hard-crashes the React Native runtime.
 */
internal class HaviInvalidBaseUrlException(cause: Throwable? = null) :
    CodedException(
        "HaviKit is enabled but config.baseUrl is missing or invalid — pass a valid HAVI_BASE_URL.",
        cause,
    )

/** Rejects `start` when the Android application context cannot be resolved. */
internal class HaviContextLostException :
    CodedException("HaviKit could not resolve the Android application context to start the SDK.")

class HaviKitModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("HaviKit")

        AsyncFunction("start") { config: HaviStartConfig ->
            val applicationContext =
                appContext.reactContext?.applicationContext ?: throw HaviContextLostException()

            val meta =
                mapOf(
                    "HAVI_ENABLED" to if (config.enabled) "true" else null,
                    "HAVI_BASE_URL" to config.baseUrl.trim().ifEmpty { null },
                    "HAVI_WORKSPACE_ID" to config.workspaceId,
                    "HAVI_PROJECT" to config.project,
                    "HAVI_WORKTREE" to config.worktree,
                    "HAVI_BRANCH" to config.branch,
                    "HAVI_COMMIT" to config.commit,
                    "HAVI_IMAGE_FORMAT" to config.imageFormat,
                    "HAVI_DEV_TOKEN" to config.devToken,
                )

            val resolved =
                try {
                    HaviConfig.fromMetaData(meta)
                } catch (error: IllegalStateException) {
                    throw HaviInvalidBaseUrlException(error)
                }

            Havi.start(applicationContext, resolved)
        }

        Function("capture") { screen: String? ->
            Havi.triggerCapture(screen)
        }

        Function("log") { message: String, level: String?, category: String? ->
            Havi.log(message, parseLogLevel(level), category ?: "app")
        }

        Function("logNetworkError") { message: String ->
            Havi.logNetworkError(message)
        }

        Function("setContext") { namespace: String, values: Map<String, String> ->
            Havi.setContext(namespace, values)
        }

        Function("setTag") { key: String, value: String ->
            Havi.setTag(key, value)
        }

        Function("setScreen") { name: String? ->
            Havi.setScreen(name)
        }

        Function("setPriority") { priority: String? ->
            Havi.setPriority(parsePriority(priority))
        }

        Function("signIn") { token: String, workspaceId: String ->
            Havi.signIn(token, workspaceId)
        }

        Function("disconnect") {
            Havi.disconnect()
        }

        Function("signOut") {
            Havi.signOut()
        }

        AsyncFunction("getAuthState") {
            when (val state = Havi.authState) {
                is HaviAuthState.Unconfigured -> mapOf("status" to "unconfigured")
                is HaviAuthState.Authenticated ->
                    mapOf("status" to "authenticated", "workspaceId" to state.workspaceId)
                is HaviAuthState.NeedsReconnect -> mapOf("status" to "needsReconnect")
            }
        }

        Function("getIsEnabled") {
            Havi.isEnabled
        }
    }
}

/** Tolerant wire-value parse (parity with iOS `HaviLogLevel(rawValue:) ?? .info`). */
private fun parseLogLevel(raw: String?): HaviLogLevel =
    when (raw?.trim()?.lowercase()) {
        "debug" -> HaviLogLevel.DEBUG
        "warning" -> HaviLogLevel.WARNING
        "error" -> HaviLogLevel.ERROR
        else -> HaviLogLevel.INFO
    }

/** Tolerant wire-value parse; `null` clears the seeded priority. */
private fun parsePriority(raw: String?): HaviPriority? =
    when (raw?.trim()?.lowercase()) {
        "high" -> HaviPriority.HIGH
        "medium" -> HaviPriority.MEDIUM
        "low" -> HaviPriority.LOW
        else -> null
    }
