// Settings: a hub and four panes.
//
// The hub restates whatever the panes hold. That is its whole purpose — a
// settings screen that only lists labels is a settings screen you have to open
// four times to check anything. DESIGN's rule: the hub row is LIVE, "four lines
// that state the truth", not four links with a title.
//
// Re-entering Settings always lands on the hub, never on the last pane used.
// That is not memory, it is an admission that we did not know what you came
// back for.
//
// EVERY CONTROL HERE DOES SOMETHING. The previous version had rows that reported
// "no key saved — nothing to test", a MiMo card whose tap said "MiMo needs a key
// — see below" with nothing below it, and an Appearance row that borrowed
// `PlanField.reader`'s label so the surface's name appeared under the word
// READER. A settings screen full of controls that explain why they cannot be used
// is a worse thing than no settings screen, so each pane below is wired to a real
// write and a real test.

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/back_label.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/texture.dart' show Hairline;
import '../../data/audio.dart';
import '../../data/remote/api.dart';
import '../../domain/plan.dart';

enum Pane { hub, topics, voice, writer, smallPrint }

/// Everything the panes need to read and write, handed in from main so this
/// screen holds no state of its own beyond which pane is open.
class SettingsModel {
  const SettingsModel({
    required this.plan,
    required this.writerId,
    required this.writerBase,
    required this.writerKeySaved,
    required this.voiceSource,
    required this.voiceBase,
    required this.voiceName,
    required this.voiceKeySaved,
    required this.deviceVoice,
    required this.paletteName,
    required this.dictionaryEntries,
  });

  final ReadingPlan plan;

  /// Which writer is selected. 'deepseek' | 'openai' | 'mimo'.
  final String writerId;
  final String writerBase;
  final bool writerKeySaved;

  /// 'device' | 'mimo'.
  final String voiceSource;
  final String voiceBase;
  final String voiceName;
  final bool voiceKeySaved;
  final DeviceVoice deviceVoice;

  final String paletteName;

  /// 0 while the dictionary is still inflating. Shown honestly rather than
  /// hidden, because "392,695 words" is the promise and its absence is a fault.
  final int dictionaryEntries;

  bool get hasWriter => writerKeySaved;
  bool get hasVoice => voiceSource == 'mimo' ? voiceKeySaved : true;

  WriterEndpoint get writer => WriterEndpoint.byId(writerId);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.model,
    required this.onBack,
    required this.onPlanChanged,
    required this.onToggleAppearance,
    required this.onWriterSelected,
    required this.onWriterBaseChanged,
    required this.onWriterKeyChanged,
    required this.onVoiceSelected,
    required this.onVoiceBaseChanged,
    required this.onVoiceNameChanged,
    required this.onVoiceKeyChanged,
    required this.onProbeVoice,
    required this.onTestWriter,
  });

  final SettingsModel model;

  final VoidCallback onBack;
  final void Function(ReadingPlan plan) onPlanChanged;
  final VoidCallback onToggleAppearance;

  final void Function(String id) onWriterSelected;
  final void Function(String base) onWriterBaseChanged;
  final void Function(String key) onWriterKeyChanged;

  final void Function(String source) onVoiceSelected;
  final void Function(String base) onVoiceBaseChanged;
  final void Function(String name) onVoiceNameChanged;
  final void Function(String key) onVoiceKeyChanged;

  /// Both return null on success or a sentence to show.
  final Future<String?> Function() onProbeVoice;
  final Future<String?> Function() onTestWriter;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Pane _pane = Pane.hub;

  /// Set while a network call is in flight, so the pane can say "asking…" and the
  /// button can refuse a second press rather than firing two requests.
  bool _working = false;

  void _go(Pane p) => setState(() => _pane = p);

  SettingsModel get m => widget.model;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return PageScaffold(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 4, Gap.gutter, 0),
            child: Row(
              children: <Widget>[
                BackLabel(
                  label: _pane == Pane.hub ? '‹ Queue' : '‹ Settings',
                  onTap: _pane == Pane.hub ? widget.onBack : () => _go(Pane.hub),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (_pane) {
              Pane.hub => _hub(c),
              Pane.topics => _topics(c),
              Pane.voice => _voice(c),
              Pane.writer => _writer(c),
              Pane.smallPrint => _smallPrint(c),
            },
          ),
        ],
      ),
    );
  }

  // ── the hub: four live lines, not four links ──────────────────────────

  Widget _hub(Palette c) {
    final ReadingPlan p = m.plan;
    final int set = p.fieldsSet;
    final String planLine = set == 0
        ? 'nothing set — picked for you'
        : '$set of 7 fields set · ${p.topics.isEmpty ? 'any topic' : p.topics.join(', ')}';

    // A phone with no speech engine is a real state, and hiding it behind a
    // settings row means the reader finds out by pressing play and hearing
    // nothing. So the hub row states it outright.
    final String voiceLine;
    if (m.voiceSource == 'device') {
      voiceLine = m.deviceVoice.available
          ? 'on-device · free · offline'
          : 'on-device selected · ${m.deviceVoice.note}';
    } else {
      voiceLine = m.voiceKeySaved
          ? 'MiMo · ${m.voiceName} · free · online'
          : 'MiMo selected · no key saved yet';
    }

    final String writerLine = m.writerKeySaved
        ? '${m.writer.name} · a key is saved · ${m.writer.costLine}'
        : 'no key · the app works fully without one';

    final String dictLine = m.dictionaryEntries == 0
        ? 'inflating on first run…'
        : '${_commas(m.dictionaryEntries)} words · offline · \$0.00';

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        const Eyebrow('Settings'),
        Text('Four things, stated plainly', style: context.texts.titleLarge),
        const SizedBox(height: 18),
        _hubRow(c, 'What you read', planLine, () => _go(Pane.topics)),
        _hubRow(c, 'Voice', voiceLine, () => _go(Pane.voice)),
        _hubRow(c, 'Who writes', writerLine, () => _go(Pane.writer)),
        _hubRow(
          c,
          'The small print',
          '${m.paletteName} · $dictLine',
          () => _go(Pane.smallPrint),
        ),
        const SizedBox(height: 20),
        Text(
          'Nothing here is required. The app works with every one of these at '
          'its default.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13.5,
            height: 1.65,
            color: c.ink3,
          ),
        ),
      ],
    );
  }

  Widget _hubRow(Palette c, String title, String value, VoidCallback tap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: TypeScale.sans,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        fontFamily: TypeScale.serif,
                        fontSize: 13.5,
                        height: 1.5,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('›', style: TextStyle(fontSize: 19, color: c.ink3)),
            ],
          ),
        ),
      ),
    );
  }

  // ── What you read: the seven named fields, one per row ────────────────

  Widget _topics(Palette c) {
    final ReadingPlan p = m.plan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('What you read', style: context.texts.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Read before every article, so detail here costs nothing per article.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 18),
        for (final PlanField f in PlanField.values)
          _FieldRow(
            field: f,
            value: _valueOf(p, f),
            onTap: () => _editField(f),
          ),
        const SizedBox(height: 18),
        Btn(
          label: 'Edit my own words',
          primary: false,
          onPressed: () => _editRaw(),
        ),
        const SizedBox(height: 10),
        Text(
          p.raw.isEmpty
              ? 'You have not written anything in your own words. A sentence '
                  'the app cannot hold in a field still reaches the writer.'
              : 'Your words: “${p.raw}”',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: c.ink3,
          ),
        ),
      ],
    );
  }

  String _valueOf(ReadingPlan p, PlanField f) => switch (f) {
        PlanField.reader => p.reader.isEmpty ? 'not set' : p.reader,
        PlanField.topics =>
          p.topics.isEmpty ? 'any topic' : p.topics.join(' · '),
        PlanField.style => p.style.isEmpty ? 'not set' : p.style.join(' · '),
        PlanField.gloss => p.gloss.isEmpty ? 'not set' : p.gloss.join(' · '),
        PlanField.avoid => p.avoid.isEmpty ? 'not set' : p.avoid.join(' · '),
        PlanField.length => '${p.length} words',
        PlanField.marked => '${p.marked} words marked',
      };

  /// One plan field. Tappable — "edit" is a word, and a word that does nothing is
  /// worse than no word at all, so the whole row is the button.
  Widget _FieldRow({
    required PlanField field,
    required String value,
    required VoidCallback onTap,
  }) {
    final Palette c = context.colors;
    final bool empty = value == 'not set' || value == 'any topic';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 13, bottom: 3),
              child: Row(
                children: <Widget>[
                  Text(
                    field.label.toUpperCase(),
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10,
                      letterSpacing: 0.14,
                      color: empty ? c.ink3 : c.verm,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'edit',
                    style: TextStyle(
                      fontFamily: TypeScale.sans,
                      fontSize: 11,
                      color: c.ink3,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 14.5,
                height: 1.55,
                color: empty ? c.ink3 : c.ink,
              ),
            ),
            Hairline(color: c.hair),
          ],
        ),
      ),
    );
  }

  /// The reader's own words. Sent VERBATIM on top of the structured fields, and
  /// never dropped by an edit elsewhere — DESIGN is explicit that Ask-the-AI
  /// edits fields, it does not eat this.
  Future<void> _editRaw() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'My own words',
      hint: 'Anything a field cannot hold',
      note: 'Sent to the writer exactly as written, on top of every field '
          'above. Editing a field never eats this.',
      initial: m.plan.raw,
    );
    if (v == null || !mounted) return;
    widget.onPlanChanged(m.plan.copyWith(raw: v));
    Toast.show(context, 'saved · the writer reads it exactly as written');
  }

  /// Edit one field. Numbers get a stepper, lists get a chip picker, and the
  /// reader's own words get a plain text box — because those are three different
  /// kinds of value and one generic text field would be wrong twice.
  Future<void> _editField(PlanField field) async {
    final ReadingPlan p = m.plan;
    ReadingPlan next = p;

    switch (field) {
      case PlanField.reader:
        final String? v = await TextPromptSheet.ask(
          context,
          title: 'Reader',
          hint: 'software developer, comfortable with code, new to finance '
              'English',
          note: 'This is the vocabulary ceiling: it tells the writer how much '
              'it may assume.',
        );
        if (v == null) return;
        next = p.copyWith(reader: v);
        break;

      case PlanField.topics:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Topics',
          note: 'Articles may only come from these.',
          initial: p.topics,
          presets: const <String>[
            'C language',
            'NVDA',
            'Music',
            'Git',
            'Reading',
            'Finance',
          ],
        );
        if (v == null) return;
        next = p.copyWith(topics: v);
        break;

      case PlanField.style:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Style',
          note: 'How it should read.',
          initial: p.style,
          presets: const <String>[
            'start with the thing itself',
            'short sentences',
            'say it once',
            'no headings',
            'concrete examples',
          ],
        );
        if (v == null) return;
        next = p.copyWith(style: v);
        break;

      case PlanField.gloss:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Explain',
          note: 'Which words get the plain-language treatment.',
          initial: p.gloss,
          presets: const <String>[
            'finance words',
            'anything where a wrong guess would be embarrassing',
            'anything with more than one meaning in this article',
          ],
        );
        if (v == null) return;
        next = p.copyWith(gloss: v);
        break;

      case PlanField.avoid:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Avoid',
          note: 'The negative space. This is the one field that can stop a '
              'fluent-but-wrong draft.',
          initial: p.avoid,
          presets: const <String>[
            'background before the point',
            'anything I already know',
            'rhetorical questions',
            'a summary at the end',
          ],
        );
        if (v == null) return;
        next = p.copyWith(avoid: v);
        break;

      case PlanField.length:
        final int? v = await NumberStepSheet.ask(
          context,
          title: 'Length',
          note: 'About how many words per article.',
          value: p.length,
          min: 100,
          max: 1200,
          step: 50,
          suffix: 'words',
        );
        if (v == null) return;
        next = p.copyWith(length: v);
        break;

      case PlanField.marked:
        final int? v = await NumberStepSheet.ask(
          context,
          title: 'Marked',
          note: 'How many words may be marked at most.',
          value: p.marked,
          min: 0,
          max: 30,
          step: 1,
          suffix: 'words marked',
        );
        if (v == null) return;
        next = p.copyWith(marked: v);
        break;
    }

    if (!mounted) return;
    widget.onPlanChanged(next);
    Toast.show(context, 'saved · nothing is written until you tap Write it');
  }

  // ── Voice ─────────────────────────────────────────────────────────────

  Widget _voice(Palette c) {
    final bool device = m.voiceSource == 'device';
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('Voice', style: context.texts.titleLarge),
        const SizedBox(height: 4),
        Text(
          "Two engines. The phone's own needs nothing and works offline; MiMo "
          'is the only online one.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 18),
        _Choice(
          title: 'On-device only',
          sub: m.deviceVoice.available
              ? 'the engine already on your phone · airplane mode · \$0.00'
              : 'selected, but ${m.deviceVoice.note}',
          selected: device,
          onTap: () => widget.onVoiceSelected('device'),
        ),
        const SizedBox(height: 8),
        _Choice(
          title: 'Xiaomi MiMo',
          sub: VoiceEndpoint.mimo.costLine,
          selected: !device,
          onTap: () => widget.onVoiceSelected('mimo'),
        ),
        if (!device) ...<Widget>[
          const SizedBox(height: 18),
          const SectionLabel('MiMo connection'),
          _TapRow(
            label: 'Base URL',
            value: m.voiceBase,
            onTap: _editVoiceBase,
          ),
          _TapRow(
            label: 'API key',
            value: m.voiceKeySaved
                ? 'a key is saved in this phone'
                : 'not set — MiMo cannot be used yet',
            onTap: _editVoiceKey,
          ),
          _TapRow(
            label: 'Voice',
            value: m.voiceName,
            onTap: _editVoiceName,
          ),
          const SizedBox(height: 12),
          Btn(
            label: _working ? 'Asking…' : 'Play one word to test it',
            primary: false,
            onPressed: _working ? null : () => _probeVoice(),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.paperSunk,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.hair),
          ),
          child: Text(
            device
                ? 'No article audio is pre-built. You read in silence and tap '
                    'words; every single word still has sound, for free, in '
                    'airplane mode.'
                : 'A recorded voice is fetched once per sentence and kept on '
                    'this phone, so hearing it again costs nothing and works '
                    'offline. With no key the app says so and falls back to the '
                    "phone's own voice rather than going quiet.",
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.65,
              color: c.ink2,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editVoiceBase() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'Base URL',
      hint: VoiceEndpoint.mimo.baseUrl,
      note: 'The address requests go to, and the only address your key is ever '
          'sent to. Change it only if your provider gave you a different one.',
      initial: m.voiceBase,
      mono: true,
      saveLabel: 'Save',
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onVoiceBaseChanged(v.trim());
  }

  Future<void> _editVoiceKey() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'MiMo API key',
      hint: 'paste the key',
      note: "Stored in this phone's keystore and only ever sent to the address "
          'above. There is no server in this version, so there is nothing that '
          'could see it.',
      obscure: true,
      saveLabel: 'Save it on this phone',
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onVoiceKeyChanged(v.trim());
  }

  Future<void> _editVoiceName() async {
    // Not `const`: a property read off a const object is not itself a constant
    // expression, so this has to be a final.
    final List<String> names = VoiceEndpoint.mimo.voices;
    final List<String>? v = await ChipPickerSheet.ask(
      context,
      title: 'Voice',
      note: 'MiMo publishes no list to fetch, so these are the built-in names. '
          'One of them speaks a word and you hear whether you like it.',
      initial: <String>[m.voiceName],
      presets: names,
    );
    if (v == null || v.isEmpty || !mounted) return;
    widget.onVoiceNameChanged(v.first);
  }

  Future<void> _probeVoice() async {
    setState(() => _working = true);
    final String? problem = await widget.onProbeVoice();
    if (!mounted) return;
    setState(() => _working = false);
    Toast.show(
      context,
      problem ?? 'that voice spoke · it is now the one this app uses',
      duration: const Duration(milliseconds: 3200),
    );
  }

  // ── Who writes ────────────────────────────────────────────────────────

  Widget _writer(Palette c) {
    final WriterEndpoint ep = m.writer;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('Who writes', style: context.texts.titleLarge),
        const SizedBox(height: 4),
        Text(
          'A list of access points, not one choice. Switching is free and '
          'rewrites nothing already written.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 18),
        for (final WriterEndpoint e in WriterEndpoint.all) ...<Widget>[
          _Choice(
            title: e.name,
            sub: e.costLine,
            selected: e.id == m.writerId,
            onTap: () => widget.onWriterSelected(e.id),
          ),
          const SizedBox(height: 8),
        ],
        const SectionLabel('Connection'),
        _TapRow(
          label: 'Base URL',
          value: m.writerBase,
          onTap: () => _editWriterBase(ep),
        ),
        _TapRow(
          label: 'API key',
          value: m.writerKeySaved
              ? 'a key is saved in this phone'
              : 'not set — writing stays switched off',
          onTap: _editWriterKey,
        ),
        const SizedBox(height: 12),
        Btn(
          label: _working ? 'Asking…' : 'Test the key',
          primary: false,
          onPressed: _working || !m.writerKeySaved
              ? null
              : () => _testWriter(ep),
        ),
        const SizedBox(height: 6),
        Text(
          m.writerKeySaved
              ? 'A test is one short request that costs a fraction of a cent '
                  'and writes nothing.'
              : 'Save a key first. The test button stays out of the way until '
                  'there is something to test.',
          style: TextStyle(
            fontFamily: TypeScale.sans,
            fontSize: 11.5,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.paperSunk,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.hair),
          ),
          child: Text(
            "Your key is stored in this phone's own keystore and only ever goes "
            'to the address above. There is no server: this version does not '
            'sell a service, so there is nothing to sell your key to.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.65,
              color: c.ink2,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editWriterBase(WriterEndpoint ep) async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'Base URL',
      hint: ep.baseUrl,
      note: 'Where article-writing requests go, and the only address the key '
          'is ever sent to.',
      initial: m.writerBase,
      mono: true,
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onWriterBaseChanged(v.trim());
  }

  Future<void> _editWriterKey() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'API key',
      hint: 'paste the key',
      note: "Stored in this phone's keystore. Writing only ever happens when "
          'you tap Write it on a card — nothing is generated on its own, ever.',
      obscure: true,
      saveLabel: 'Save it on this phone',
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onWriterKeyChanged(v.trim());
  }

  Future<void> _testWriter(WriterEndpoint ep) async {
    setState(() => _working = true);
    final String? problem = await widget.onTestWriter();
    if (!mounted) return;
    setState(() => _working = false);
    Toast.show(
      context,
      problem ?? '${ep.name} answered. Nothing was written.',
      duration: const Duration(milliseconds: 3200),
    );
  }

  // ── The small print: appearance, storage, the dictionary ──────────────

  Widget _smallPrint(Palette c) {
    final int entries = m.dictionaryEntries;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('The small print', style: context.texts.titleLarge),
        const SizedBox(height: 18),
        const SectionLabel('Appearance'),
        // Its OWN row, with its own label. This used to borrow PlanField.reader
        // so the surface's name appeared under the word READER, next to the
        // reader's own description — two unrelated facts sharing one label.
        _TapRow(
          label: 'Surface',
          value: m.paletteName,
          onTap: widget.onToggleAppearance,
        ),
        const SizedBox(height: 10),
        Btn(
          label: 'Switch surface',
          primary: false,
          onPressed: widget.onToggleAppearance,
        ),
        const SizedBox(height: 6),
        Text(
          'Two surfaces, chosen once. There is no day and no night in this app '
              '— that distinction was removed rather than renamed, so nothing '
              'here changes with the clock.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: c.ink3,
          ),
        ),
        const SectionLabel('Dictionary'),
        Text(
          entries == 0
              ? 'inflating on first run…'
              : '${_commas(entries)} words · offline · \$0.00 · never a network call',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 14.5,
            height: 1.55,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A word this dictionary does not carry is reported as missing rather '
              'than looked up somewhere. That is the whole trade: \$0.00, '
              'airplane mode, and an honest "not in there".',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: c.ink3,
          ),
        ),
        const SectionLabel('What this app will not do'),
        for (final String line in const <String>[
          'ask whether you remember a word',
          'give you a streak, a score, or a percentage',
          'delete anything you read — freeing space only removes the file',
          'schedule anything, or write on its own',
          'look a word up over the network',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('·', style: TextStyle(color: c.verm, fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: TypeScale.serif,
                      fontSize: 13.5,
                      height: 1.55,
                      color: c.ink2,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _commas(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (Match m) => '${m[1]},');
}

/// A label/value row that is also the button that changes it.
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 13, bottom: 3),
              child: Row(
                children: <Widget>[
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10,
                      letterSpacing: 0.14,
                      color: c.ink3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'edit',
                    style: TextStyle(
                      fontFamily: TypeScale.sans,
                      fontSize: 11,
                      color: c.ink3,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 12.5,
                height: 1.5,
                color: c.ink,
              ),
            ),
            Hairline(color: c.hair),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: selected ? c.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.verm : c.hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: TypeScale.sans,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontFamily: TypeScale.serif,
                        fontSize: 13,
                        height: 1.5,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: 8),
                Icon(Icons.check, size: 16, color: c.verm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}