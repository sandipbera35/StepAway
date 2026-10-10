package io.github.sandipbera35.stepaway.wear

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.ToggleChip
import androidx.wear.compose.material.ToggleChipDefaults
import androidx.wear.compose.material.Scaffold

class MainActivity : ComponentActivity() {
    private lateinit var state: WearState

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        state = WearState(this)
        setContent { WearApp(state) }
    }

    override fun onResume() {
        super.onResume()
        state.refresh()
    }

    override fun onDestroy() {
        state.cancelPairing()
        super.onDestroy()
    }
}

private val Indigo = Color(0xFF8B8CFF)
private val Cyan = Color(0xFF22D3EE)
private val Mint = Color(0xFF34D399)

private val colors = Colors(
    primary = Indigo,
    primaryVariant = Color(0xFF6366F1),
    secondary = Cyan,
    secondaryVariant = Color(0xFF0E9AB0),
    background = Color.Black,
    surface = Color(0xFF151A3A),
    error = Color(0xFFF87171),
    onPrimary = Color.Black,
    onSecondary = Color.Black,
    onBackground = Color(0xFFF3F5FF),
    onSurface = Color(0xFFF3F5FF),
    onSurfaceVariant = Color(0xFF9AA4C4),
    onError = Color.Black,
)

/** The permissions the watch needs to broadcast, to confirm a pairing and to show its notification. */
private fun neededPermissions(): Array<String> = buildList {
    if (Build.VERSION.SDK_INT >= 31) {
        add(Manifest.permission.BLUETOOTH_ADVERTISE)
        add(Manifest.permission.BLUETOOTH_SCAN)
        add(Manifest.permission.BLUETOOTH_CONNECT)
    } else {
        add(Manifest.permission.ACCESS_FINE_LOCATION)
    }
    if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
}.toTypedArray()

@Composable
fun WearApp(state: WearState) {
    MaterialTheme(colors = colors) {
        var removing by remember { mutableStateOf<Pairing?>(null) }
        val askPermissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { state.refresh() }
        Scaffold(timeText = { TimeText() }) {
            val session = state.session
            when {
                session != null -> PairingScreen(state, session)
                removing != null -> RemoveScreen(removing!!, onConfirm = { state.remove(it.deviceId); removing = null }, onCancel = { removing = null })
                else -> HomeScreen(
                    state,
                    onToggle = { on ->
                        if (on) askPermissions.launch(neededPermissions())
                        state.toggleProtection(on)
                    },
                    onPair = {
                        askPermissions.launch(neededPermissions())
                        state.startPairing()
                    },
                    onRemove = { removing = it },
                )
            }
        }
    }
}

@Composable
private fun HomeScreen(state: WearState, onToggle: (Boolean) -> Unit, onPair: () -> Unit, onRemove: (Pairing) -> Unit) {
    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(modifier = Modifier.fillMaxSize(), state = listState, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            Text("StepAway", style = MaterialTheme.typography.title2, color = MaterialTheme.colors.primary)
        }
        item {
            val status = when {
                state.pairings.isEmpty() -> "Not paired yet"
                !state.protection -> "Protection is off"
                state.advertising -> "You are protected"
                else -> state.problem ?: "Starting..."
            }
            Text(status, style = MaterialTheme.typography.caption1, textAlign = TextAlign.Center, color = if (state.advertising) Mint else MaterialTheme.colors.onSurfaceVariant)
        }
        if (state.pairings.isNotEmpty()) {
            item {
                ToggleChip(
                    modifier = Modifier.fillMaxWidth(),
                    checked = state.protection,
                    onCheckedChange = onToggle,
                    label = { Text("Protection") },
                    toggleControl = { androidx.wear.compose.material.Switch(checked = state.protection, onCheckedChange = null) },
                    colors = ToggleChipDefaults.toggleChipColors(),
                )
            }
        }
        item {
            Chip(
                modifier = Modifier.fillMaxWidth(),
                onClick = onPair,
                label = { Text("Pair with a code") },
                secondaryLabel = { Text("For your computer", maxLines = 1) },
                colors = ChipDefaults.primaryChipColors(),
            )
        }
        for (p in state.pairings) {
            item {
                Chip(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { onRemove(p) },
                    label = { Text(p.desktopName, maxLines = 1) },
                    secondaryLabel = { Text("Tap to remove", maxLines = 1) },
                    colors = ChipDefaults.secondaryChipColors(),
                )
            }
        }
    }
}

@Composable
private fun PairingScreen(state: WearState, session: PairingSession) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 14.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (state.paired) {
            Text("Paired!", style = MaterialTheme.typography.title1, color = Mint)
            Spacer(Modifier.height(8.dp))
            Text("Your computer can now tell when you step away.", style = MaterialTheme.typography.caption1, textAlign = TextAlign.Center)
            Spacer(Modifier.height(10.dp))
            Chip(onClick = { state.closePairing() }, label = { Text("Done") }, colors = ChipDefaults.primaryChipColors())
        } else {
            Text("Type this code on your computer", style = MaterialTheme.typography.caption1, textAlign = TextAlign.Center)
            Spacer(Modifier.height(6.dp))
            for (line in session.codeLines) {
                Text(
                    line,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    fontSize = 21.sp,
                    color = MaterialTheme.colors.secondary,
                )
            }
            Spacer(Modifier.height(8.dp))
            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
            Spacer(Modifier.height(4.dp))
            Text(state.problem ?: "Waiting for your computer...", style = MaterialTheme.typography.caption2, textAlign = TextAlign.Center)
            Spacer(Modifier.height(6.dp))
            Chip(onClick = { state.cancelPairing() }, label = { Text("Cancel") }, colors = ChipDefaults.secondaryChipColors())
        }
    }
}

@Composable
private fun RemoveScreen(p: Pairing, onConfirm: (Pairing) -> Unit, onCancel: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 14.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("Remove ${p.desktopName}?", style = MaterialTheme.typography.title3, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Chip(onClick = { onConfirm(p) }, label = { Text("Remove") }, colors = ChipDefaults.primaryChipColors())
        Chip(onClick = onCancel, label = { Text("Keep") }, colors = ChipDefaults.secondaryChipColors())
    }
}
