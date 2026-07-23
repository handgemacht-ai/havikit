package ai.handgemacht.havikit

/**
 * A scripted [HaviHttpTransport] for the state-machine tests: enqueue responses
 * (or a transport failure) and each [execute] consumes the next one, recording the
 * request. Mirrors the role the iOS tests' `StubURLProtocol` plays.
 */
class StubTransport : HaviHttpTransport {
    private sealed interface Step {
        data class Respond(val status: Int, val body: ByteArray) : Step

        data object Fail : Step
    }

    private val steps = ArrayDeque<Step>()
    val requests = mutableListOf<HaviHttpRequest>()

    val consumedCount: Int get() = requests.size

    fun enqueue(
        status: Int,
        json: String,
    ): StubTransport {
        steps.addLast(Step.Respond(status, json.toByteArray(Charsets.UTF_8)))
        return this
    }

    fun enqueueFailure(): StubTransport {
        steps.addLast(Step.Fail)
        return this
    }

    override fun execute(request: HaviHttpRequest): HaviHttpResponse {
        requests += request
        return when (val step = steps.removeFirstOrNull() ?: error("no stubbed response for ${request.url}")) {
            is Step.Respond -> HaviHttpResponse(step.status, step.body)
            Step.Fail -> throw HaviTransportException("stubbed transport failure")
        }
    }
}
