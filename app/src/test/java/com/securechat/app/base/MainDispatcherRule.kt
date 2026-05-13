package com.securechat.app.base

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.rules.TestWatcher
import org.junit.runner.Description

/**
 * JUnit Rule — `Dispatchers.Main`'i test'te swap eder.
 *
 * ViewModel `viewModelScope.launch` Main dispatcher'ı kullanır; test JVM'inde
 * Main dispatcher'ın initialize edilmesi gerekir. Bu Rule bunu otomatik yapar:
 *   - `@Before`'da `Dispatchers.setMain(testDispatcher)`
 *   - `@After`'da `Dispatchers.resetMain()`
 *
 * Kullanım:
 * ```
 * @get:Rule val mainDispatcherRule = MainDispatcherRule()
 * ```
 *
 * @param testDispatcher Varsayılan `StandardTestDispatcher` — manuel `advanceUntilIdle` ile
 *                       deterministic kontrol sağlar. Anlık execution için `UnconfinedTestDispatcher`
 *                       parametre olarak verilebilir.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    val testDispatcher: TestDispatcher = StandardTestDispatcher()
) : TestWatcher() {
    override fun starting(description: Description) {
        Dispatchers.setMain(testDispatcher)
    }

    override fun finished(description: Description) {
        Dispatchers.resetMain()
    }
}
