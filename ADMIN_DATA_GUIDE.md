# Using the MaxPlayer admin data

The dashboard helps answer **what is being used, what may be broken, and what to improve next**. It is aggregate operational data, not a list of identified people or a complete product-analytics platform.

## A practical weekly routine
1. Choose a complete 7-day period and export a PDF. Repeat for the previous 7 days. Compare equal-length windows; avoid comparing a partial day with a whole day.
2. Compare app opens, videos, direct streams and IPTV plays. Look for sustained changes, not one small spike. Note your release date, version and any notification sent.
3. Select each of the eight feature-open metrics. Prioritise frequently used features for polish. For low-use features, investigate discoverability and usefulness before removing them.
4. Read problem reports. Group similar messages manually, check app version/time, reproduce the problem, fix it and see whether similar reports recur. A version in a diagnostic report does not make the aggregate activity charts version-segmented.
5. Look at the country sample for language/localisation ideas and device-local hours for broad communication timing. Send a test to one installation before an All notification. This panel does not automate notification scheduling or target a country-chart group.
6. Keep the exports and a short decision note, for example: “Audio opens rose over two full weeks; investigate audio issues before changing the player UI.” Treat correlation as a clue, not proof that a release caused a change.

## What each number can and cannot tell you
| Data | Useful for | Important limitation |
| --- | --- | --- |
| App opens | Comparing overall recorded activity across equal periods | Opens are events, not daily/monthly active users |
| Videos played | Assessing recorded local-video playback activity | Not unique viewers, completed watches or unique files |
| Streams opened / IPTV plays | Seeing recorded network/TV usage | Counts do not establish that playback succeeded or finished |
| Eight feature opens | Choosing features to improve: Discover, Private, Folders, Playlists, Audio, Network, Cloud, Quick Share | Different event types are not a conversion funnel; Private open does not mean unlock |
| Average foreground session | A rough recorded engagement trend | Not guaranteed watch time; interrupted/abrupt sessions may be missed |
| Install registrations | Cumulative installation-registration trend; daily history since +71 | Not current installed devices, unique people or uninstall counts; reinstall/data-clear can register again |
| Country sample | Broad language/content planning | Approximate first successful IP lookup since +69, all-time including upgrades; not GPS/current residence/religion or historical download country |
| Hour-of-day opens | Broad local-time activity patterns | Aggregated device-local hours, not a single UTC audience schedule |
| App problem reports | Finding reproducible Flutter/uncaught Dart issues | Incomplete capture; not all native crashes, ANRs or process kills; not an exact crash-free-user percentage |
| Notification status | Checking whether the sender/FCM accepted a request | Not phone-delivery, read or click confirmation |

Core activity windows, feature mix and hours follow the selected dates. The install-registration summary and IP-country chart are all-time. Feature opens start with +70, daily install registrations with +71, and IP samples with +69; missing earlier history is not proof of zero activity. Offline/queued updates, old installed APKs and missed events can distort comparisons.

## What you cannot calculate accurately from these aggregates
- User-level retention (D1/D7/D30), unique DAU/MAU or per-user funnels.
- Exact current installs, uninstall totals or individual activity histories.
- Religion, personal identity, precise location or verified citizenship.
- Ad earnings/revenue, full-film completion or confirmed notification conversion.

Use the appropriate Play Console or advertising reports for their own measurements; do not manufacture those values from app-open/registration counters.

## Export and reset
PDF export includes selected-date chart visuals plus all fetched stored analytics and report appendices, not the entire database. It deliberately excludes device tokens, credentials and admin account records. Full diagnostic text can contain technical context: keep the PDF private and redact before sharing. It is not an atomic backup.

Do not reset just to view a new week: use the date filter. Reset is irreversible, privileged and limited to stats/reports. Export first. Other records are preserved; active/offline apps can submit new or queued events afterwards. Resetting does not reset the once-per-install country/registration flags, so installation totals will not automatically recount your installed base.

No arbitrary-dataset upload, CSV importer, automatic marketing attribution or user-profiling system is added by this guide.
