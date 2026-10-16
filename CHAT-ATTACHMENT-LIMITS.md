# Chat attachment limits for recording exports

Checked **2026-10-16** against the official pages and Signal source linked below. These are ordinary user-client attachment limits, not bot API limits. Proposed export budgets include headroom; they are implementation choices, not provider guarantees. Unless explicitly stated otherwise, a provider's “MB”/“GB” notation does **not** establish decimal versus binary bytes.

## Verified limits and proposed budgets

| Destination | Verified published limit / source | Conservative export budget (bytes) |
| --- | --- | ---: |
| Discord free | **20MB** per file; upload-limit experiments may change an account's entitlement. [File Attachments FAQ](https://support.discord.com/hc/en-us/articles/25444343291031-File-Attachments-FAQ), updated September 30, 2026. | 19,000,000 |
| Discord Nitro Basic | **50 MB**. [Nitro comparison](https://support.discord.com/hc/en-us/articles/115000435108-What-are-Nitro-Nitro-Basic) | 47,000,000 |
| Discord Nitro | **Up to 1GB**. [Nitro comparison](https://support.discord.com/hc/en-us/articles/115000435108-What-are-Nitro-Nitro-Basic) | 950,000,000 |
| Discord boosted server, Level 1 | No upload increase is listed for Level 1; use the sender's ordinary entitlement. [Server Boosting FAQ](https://support.discord.com/hc/en-us/articles/360028038352-Server-Boosting-FAQ) | 19,000,000 for a free sender |
| Discord boosted server, Level 2 | **50MB**, all members, **inside that server only**; Level 2 takes 7 boosts. [Server Boosting FAQ](https://support.discord.com/hc/en-us/articles/360028038352-Server-Boosting-FAQ) | 47,000,000 |
| Discord boosted server, Level 3 | **100MB**, all members, **inside that server only**; Level 3 takes 14 boosts. Some servers are in an experiment offering **250MB** uploads as a separate 5-boost perk. [Server Boosting FAQ](https://support.discord.com/hc/en-us/articles/360028038352-Server-Boosting-FAQ) | 95,000,000; experimental perk: 235,000,000 only if confirmed |
| Signal Desktop | Source defaults: video **104,857,600 bytes (100 MiB)**; generic attachments separately default to the same amount. Both are remotely configurable; the size check uses padded/encrypted attachment size, so the raw file cannot safely occupy the whole ceiling. [Desktop source](https://github.com/signalapp/Signal-Desktop/blob/f3040f3e13b6dca5021c3db149320e0f7a771f0a/ts/types/AttachmentSize.std.ts) | 95,000,000 |
| Signal Android | Generic **ciphertext** default **104,857,600 bytes**; video transcode target independently defaults to the same amount. Source videos can default to **1,073,741,824 bytes (1 GiB)** for transcoding: that is an **input** allowance, not an outgoing attachment allowance. Values are remotely configurable. [RemoteConfig](https://github.com/signalapp/Signal-Android/blob/db06ef04799796836b773164b49e018f5ec87dc9/app/src/main/java/org/thoughtcrime/securesms/util/RemoteConfig.kt), [PushMediaConstraints](https://github.com/signalapp/Signal-Android/blob/db06ef04799796836b773164b49e018f5ec87dc9/app/src/main/java/org/thoughtcrime/securesms/mms/PushMediaConstraints.java) | 95,000,000 |
| Signal iOS | Generic encrypted attachment default **104,857,600 bytes**; video has a separate remote flag and defaults to the generic encrypted limit. The source's 1,610,612,736-byte hard bound is a safety ceiling, **not** the default entitlement. [RemoteConfigManager](https://github.com/signalapp/Signal-iOS/blob/d13b9da9e4622e16297b111243755c4c2972091a/SignalServiceKit/Environment/RemoteConfigManager.swift) | 95,000,000 |
| WhatsApp ordinary video | The current **Web-client help page** says faster connections default to **100MB / 720p**, slower connections to **64MB / 480p**. It does not establish an invariant size cap for every mobile version or delivery path. [Send media](https://faq.whatsapp.com/453914586839706?cms_platform=web) | 60,000,000; 480p is the conservative interoperability resolution |
| WhatsApp document | **2 GB** via the Document picker, a distinct path from Photos & Videos. [Send media](https://faq.whatsapp.com/453914586839706?cms_platform=web) | 1,900,000,000 |
| Telegram free | Files **and media**, **2 GB each**. [Official announcement](https://telegram.org/blog/700-million-and-premium), [current FAQ](https://telegram.org/faq) | 1,900,000,000 |
| Telegram Premium | **4 GB each**; free users can download these larger files from subscribers. [Premium FAQ](https://telegram.org/faq_premium), [official announcement](https://telegram.org/blog/700-million-and-premium) | 3,800,000,000 |
| Slack | Files **up to 1GB**; the upload instructions state no paid-plan increase. Slack Connect upload/type restrictions and malware scanning can independently prevent an upload. [Add files](https://slack.com/help/articles/201330736-Add-files-to-Slack) | 950,000,000 |
| Microsoft Teams chat | Current **Chat** limits table explicitly says **100 MB**, maximum 10 attachments. Do not infer that every chat upload supports the SharePoint maximum. [Teams limits](https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams), updated August 25, 2026. | 95,000,000 |
| Microsoft Teams Files / SharePoint | **250 GB per file** in the listed Microsoft 365/Office 365 organizational plans, subject to backing storage and tenant configuration. Email-to-channel is a separate path with attachments **less than 10 MB**. [Teams limits](https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams) | Use the 95,000,000 chat preset for routine sharing; handle large Files uploads separately |

## Format and playback

- **Recommended export:** MP4 container, H.264/AVC video, AAC audio when audio exists, 8-bit `yuv420p`, even dimensions, and a front-loaded MP4 index (`faststart`). This is a conservative engineering preset, not an assertion that all services require precisely these settings. Microsoft explicitly recommends **MP4 + H.264 + AAC**, 30 fps, and AAC at 384 Kbps or less. [Microsoft playback guidance](https://support.microsoft.com/en-us/onedrive/video-formats-you-can-play-on-microsoft-365)
- Discord explicitly lists MOV and MP4, including MP4 encoded with H.264, HEVC/H.265 or AV1. Acceptance of those codecs does not establish universal recipient-device playback. Prefer H.264 for the shared preset. [Discord attachment formats](https://support.discord.com/hc/en-us/articles/25444343291031-File-Attachments-FAQ)
- WhatsApp's Web help lists 3GP, AVI, FLV, MKV, MOV and MP4, while warning that professional-camera media or high audio sample rates may be unsupported. Container extension alone is insufficient evidence of compatible encoding. Use Document intentionally for a large original instead of promising ordinary video behavior. [WhatsApp formats and separate pickers](https://faq.whatsapp.com/453914586839706?cms_platform=web)
- Signal's source explicitly separates video handling/transcoding from generic files. A source video accepted for transcoding is not evidence it can be sent unchanged at that size. Desktop's outgoing size check additionally applies encryption/padding. No current fixed live-server cap or universal codec matrix was established from the inspected sources. [Desktop size logic](https://github.com/signalapp/Signal-Desktop/blob/f3040f3e13b6dca5021c3db149320e0f7a771f0a/ts/types/AttachmentSize.std.ts), [Android media constraints](https://github.com/signalapp/Signal-Android/blob/db06ef04799796836b773164b49e018f5ec87dc9/app/src/main/java/org/thoughtcrime/securesms/mms/PushMediaConstraints.java)
- Telegram supports files of arbitrary types; arbitrary-file delivery and inline video playback are different promises. [Telegram FAQ](https://telegram.org/faq) Slack documents file upload and preview behavior but the inspected upload page does not provide a complete video codec matrix. [Slack file help](https://slack.com/help/articles/201330736-Add-files-to-Slack)

## Implementation recommendations

Treat the numbers below as **maximum final filesystem bytes**, including audio and container overhead. Aim the encoder below the budget, then measure the finished file; bitrate estimates alone cannot guarantee acceptance. Preserve the source and give each smaller derivative a distinct destination-specific name. A single free-account cross-app sharing derivative can use `discord_free` (19,000,000 bytes); app-specific derivatives can preserve more detail.

```json
{
  "format": "mp4",
  "video_codec": "h264",
  "pixel_format": "yuv420p",
  "audio_codec": "aac",
  "faststart": true,
  "budget_bytes": {
    "discord_free": 19000000,
    "discord_basic": 47000000,
    "discord_nitro": 950000000,
    "discord_server_level2": 47000000,
    "discord_server_level3": 95000000,
    "signal": 95000000,
    "whatsapp_video": 60000000,
    "whatsapp_document": 1900000000,
    "telegram": 1900000000,
    "telegram_premium": 3800000000,
    "slack": 950000000,
    "teams_chat": 95000000
  }
}
```

Remaining uncertainty: provider MB/GB units, account/server experiments, Signal remote configuration and released-client behavior, and WhatsApp mobile-specific transcoding rules. These findings are documentation/source verification, not completed upload/playback acceptance tests. The general Teams chat 100 MB statement and the Files 250 GB statement coexist in the current official page; keep both visible instead of silently substituting one for the other.
