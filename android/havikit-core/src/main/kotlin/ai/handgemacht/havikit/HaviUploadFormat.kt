package ai.handgemacht.havikit

/**
 * The multipart `image` part descriptor and local byte cap per image format (wire
 * spec §9.1). PNG is the ship default (live backend is PNG-only, 2 MiB); JPEG
 * (quality 0.7, 5 MiB) is selected by the stamped `HAVI_IMAGE_FORMAT` flag with no
 * code fork.
 */

public val HaviImageFormat.multipartFilename: String
    get() = if (this == HaviImageFormat.PNG) "screenshot.png" else "screenshot.jpg"

public val HaviImageFormat.multipartContentType: String
    get() = if (this == HaviImageFormat.PNG) "image/png" else "image/jpeg"

/** Conservative local cap before the server backstops with `payload_too_large`. */
public val HaviImageFormat.maxUploadBytes: Int
    get() = if (this == HaviImageFormat.PNG) 2_097_152 else 5_242_880
