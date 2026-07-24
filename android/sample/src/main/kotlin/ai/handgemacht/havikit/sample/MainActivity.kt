package ai.handgemacht.havikit.sample

import ai.handgemacht.havikit.Havi
import ai.handgemacht.havikit.HaviOverlay
import ai.handgemacht.havikit.haviScreen
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

private enum class SampleScreen(val title: String, val blurb: String) {
    HOME("Home", "The landing screen. Shake the device or tap “Capture feedback” to file a report against this screen."),
    DETAIL("Detail", "A stand-in detail screen. Each tab names itself to HaviKit so reports are grouped per screen."),
    PROFILE("Profile", "A stand-in profile screen. Use “Pair this device” to connect the app to a HAVI workspace."),
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                HaviOverlay {
                    SampleAppUi()
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SampleAppUi() {
    val screens = SampleScreen.entries
    var selected by rememberSaveable { mutableStateOf(0) }
    val screen = screens[selected]

    LaunchedEffect(selected) {
        Havi.log("navigated to ${screen.title}")
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("HaviKit Sample") }) },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            TabRow(selectedTabIndex = selected) {
                screens.forEachIndexed { index, item ->
                    Tab(
                        selected = index == selected,
                        onClick = { selected = index },
                        text = { Text(item.title) },
                    )
                }
            }
            ScreenBody(screen)
        }
    }
}

@Composable
private fun ScreenBody(screen: SampleScreen) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .haviScreen(screen.title)
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(screen.title, style = MaterialTheme.typography.headlineSmall)
        Text(screen.blurb, style = MaterialTheme.typography.bodyMedium)

        Spacer(Modifier.weight(1f))

        Button(
            onClick = { Havi.capture(screen = screen.title) },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Capture feedback")
        }
        OutlinedButton(
            onClick = { Havi.capture(screen = screen.title) },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Pair this device")
        }
        Text(
            "Shake the device to capture too. To pair, open a capture and tap “Connect” on the details step.",
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.align(Alignment.CenterHorizontally),
        )
    }
}
