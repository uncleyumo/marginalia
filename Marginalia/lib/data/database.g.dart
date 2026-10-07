// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $QueueRowsTable extends QueueRows
    with TableInfo<$QueueRowsTable, QueueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _articleIdMeta =
      const VerificationMeta('articleId');
  @override
  late final GeneratedColumn<String> articleId = GeneratedColumn<String>(
      'article_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
      'topic', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _focusMeta = const VerificationMeta('focus');
  @override
  late final GeneratedColumn<String> focus = GeneratedColumn<String>(
      'focus', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _plannedWordsMeta =
      const VerificationMeta('plannedWords');
  @override
  late final GeneratedColumn<int> plannedWords = GeneratedColumn<int>(
      'planned_words', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(300));
  static const VerificationMeta _plannedMarkedMeta =
      const VerificationMeta('plannedMarked');
  @override
  late final GeneratedColumn<int> plannedMarked = GeneratedColumn<int>(
      'planned_marked', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(6));
  static const VerificationMeta _isWritingMeta =
      const VerificationMeta('isWriting');
  @override
  late final GeneratedColumn<bool> isWriting = GeneratedColumn<bool>(
      'is_writing', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_writing" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        articleId,
        state,
        topic,
        focus,
        plannedWords,
        plannedMarked,
        isWriting,
        position
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_rows';
  @override
  VerificationContext validateIntegrity(Insertable<QueueRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('article_id')) {
      context.handle(_articleIdMeta,
          articleId.isAcceptableOrUnknown(data['article_id']!, _articleIdMeta));
    } else if (isInserting) {
      context.missing(_articleIdMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
          _topicMeta, topic.isAcceptableOrUnknown(data['topic']!, _topicMeta));
    }
    if (data.containsKey('focus')) {
      context.handle(
          _focusMeta, focus.isAcceptableOrUnknown(data['focus']!, _focusMeta));
    }
    if (data.containsKey('planned_words')) {
      context.handle(
          _plannedWordsMeta,
          plannedWords.isAcceptableOrUnknown(
              data['planned_words']!, _plannedWordsMeta));
    }
    if (data.containsKey('planned_marked')) {
      context.handle(
          _plannedMarkedMeta,
          plannedMarked.isAcceptableOrUnknown(
              data['planned_marked']!, _plannedMarkedMeta));
    }
    if (data.containsKey('is_writing')) {
      context.handle(_isWritingMeta,
          isWriting.isAcceptableOrUnknown(data['is_writing']!, _isWritingMeta));
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      articleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}article_id'])!,
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      topic: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}topic'])!,
      focus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}focus'])!,
      plannedWords: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}planned_words'])!,
      plannedMarked: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}planned_marked'])!,
      isWriting: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_writing'])!,
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
    );
  }

  @override
  $QueueRowsTable createAlias(String alias) {
    return $QueueRowsTable(attachedDatabase, alias);
  }
}

class QueueRow extends DataClass implements Insertable<QueueRow> {
  final int id;
  final String articleId;
  final String state;
  final String topic;
  final String focus;
  final int plannedWords;
  final int plannedMarked;
  final bool isWriting;
  final int position;
  const QueueRow(
      {required this.id,
      required this.articleId,
      required this.state,
      required this.topic,
      required this.focus,
      required this.plannedWords,
      required this.plannedMarked,
      required this.isWriting,
      required this.position});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['article_id'] = Variable<String>(articleId);
    map['state'] = Variable<String>(state);
    map['topic'] = Variable<String>(topic);
    map['focus'] = Variable<String>(focus);
    map['planned_words'] = Variable<int>(plannedWords);
    map['planned_marked'] = Variable<int>(plannedMarked);
    map['is_writing'] = Variable<bool>(isWriting);
    map['position'] = Variable<int>(position);
    return map;
  }

  QueueRowsCompanion toCompanion(bool nullToAbsent) {
    return QueueRowsCompanion(
      id: Value(id),
      articleId: Value(articleId),
      state: Value(state),
      topic: Value(topic),
      focus: Value(focus),
      plannedWords: Value(plannedWords),
      plannedMarked: Value(plannedMarked),
      isWriting: Value(isWriting),
      position: Value(position),
    );
  }

  factory QueueRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueRow(
      id: serializer.fromJson<int>(json['id']),
      articleId: serializer.fromJson<String>(json['articleId']),
      state: serializer.fromJson<String>(json['state']),
      topic: serializer.fromJson<String>(json['topic']),
      focus: serializer.fromJson<String>(json['focus']),
      plannedWords: serializer.fromJson<int>(json['plannedWords']),
      plannedMarked: serializer.fromJson<int>(json['plannedMarked']),
      isWriting: serializer.fromJson<bool>(json['isWriting']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'articleId': serializer.toJson<String>(articleId),
      'state': serializer.toJson<String>(state),
      'topic': serializer.toJson<String>(topic),
      'focus': serializer.toJson<String>(focus),
      'plannedWords': serializer.toJson<int>(plannedWords),
      'plannedMarked': serializer.toJson<int>(plannedMarked),
      'isWriting': serializer.toJson<bool>(isWriting),
      'position': serializer.toJson<int>(position),
    };
  }

  QueueRow copyWith(
          {int? id,
          String? articleId,
          String? state,
          String? topic,
          String? focus,
          int? plannedWords,
          int? plannedMarked,
          bool? isWriting,
          int? position}) =>
      QueueRow(
        id: id ?? this.id,
        articleId: articleId ?? this.articleId,
        state: state ?? this.state,
        topic: topic ?? this.topic,
        focus: focus ?? this.focus,
        plannedWords: plannedWords ?? this.plannedWords,
        plannedMarked: plannedMarked ?? this.plannedMarked,
        isWriting: isWriting ?? this.isWriting,
        position: position ?? this.position,
      );
  QueueRow copyWithCompanion(QueueRowsCompanion data) {
    return QueueRow(
      id: data.id.present ? data.id.value : this.id,
      articleId: data.articleId.present ? data.articleId.value : this.articleId,
      state: data.state.present ? data.state.value : this.state,
      topic: data.topic.present ? data.topic.value : this.topic,
      focus: data.focus.present ? data.focus.value : this.focus,
      plannedWords: data.plannedWords.present
          ? data.plannedWords.value
          : this.plannedWords,
      plannedMarked: data.plannedMarked.present
          ? data.plannedMarked.value
          : this.plannedMarked,
      isWriting: data.isWriting.present ? data.isWriting.value : this.isWriting,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueRow(')
          ..write('id: $id, ')
          ..write('articleId: $articleId, ')
          ..write('state: $state, ')
          ..write('topic: $topic, ')
          ..write('focus: $focus, ')
          ..write('plannedWords: $plannedWords, ')
          ..write('plannedMarked: $plannedMarked, ')
          ..write('isWriting: $isWriting, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, articleId, state, topic, focus,
      plannedWords, plannedMarked, isWriting, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueRow &&
          other.id == this.id &&
          other.articleId == this.articleId &&
          other.state == this.state &&
          other.topic == this.topic &&
          other.focus == this.focus &&
          other.plannedWords == this.plannedWords &&
          other.plannedMarked == this.plannedMarked &&
          other.isWriting == this.isWriting &&
          other.position == this.position);
}

class QueueRowsCompanion extends UpdateCompanion<QueueRow> {
  final Value<int> id;
  final Value<String> articleId;
  final Value<String> state;
  final Value<String> topic;
  final Value<String> focus;
  final Value<int> plannedWords;
  final Value<int> plannedMarked;
  final Value<bool> isWriting;
  final Value<int> position;
  const QueueRowsCompanion({
    this.id = const Value.absent(),
    this.articleId = const Value.absent(),
    this.state = const Value.absent(),
    this.topic = const Value.absent(),
    this.focus = const Value.absent(),
    this.plannedWords = const Value.absent(),
    this.plannedMarked = const Value.absent(),
    this.isWriting = const Value.absent(),
    this.position = const Value.absent(),
  });
  QueueRowsCompanion.insert({
    this.id = const Value.absent(),
    required String articleId,
    required String state,
    this.topic = const Value.absent(),
    this.focus = const Value.absent(),
    this.plannedWords = const Value.absent(),
    this.plannedMarked = const Value.absent(),
    this.isWriting = const Value.absent(),
    required int position,
  })  : articleId = Value(articleId),
        state = Value(state),
        position = Value(position);
  static Insertable<QueueRow> custom({
    Expression<int>? id,
    Expression<String>? articleId,
    Expression<String>? state,
    Expression<String>? topic,
    Expression<String>? focus,
    Expression<int>? plannedWords,
    Expression<int>? plannedMarked,
    Expression<bool>? isWriting,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (articleId != null) 'article_id': articleId,
      if (state != null) 'state': state,
      if (topic != null) 'topic': topic,
      if (focus != null) 'focus': focus,
      if (plannedWords != null) 'planned_words': plannedWords,
      if (plannedMarked != null) 'planned_marked': plannedMarked,
      if (isWriting != null) 'is_writing': isWriting,
      if (position != null) 'position': position,
    });
  }

  QueueRowsCompanion copyWith(
      {Value<int>? id,
      Value<String>? articleId,
      Value<String>? state,
      Value<String>? topic,
      Value<String>? focus,
      Value<int>? plannedWords,
      Value<int>? plannedMarked,
      Value<bool>? isWriting,
      Value<int>? position}) {
    return QueueRowsCompanion(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      state: state ?? this.state,
      topic: topic ?? this.topic,
      focus: focus ?? this.focus,
      plannedWords: plannedWords ?? this.plannedWords,
      plannedMarked: plannedMarked ?? this.plannedMarked,
      isWriting: isWriting ?? this.isWriting,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (articleId.present) {
      map['article_id'] = Variable<String>(articleId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (focus.present) {
      map['focus'] = Variable<String>(focus.value);
    }
    if (plannedWords.present) {
      map['planned_words'] = Variable<int>(plannedWords.value);
    }
    if (plannedMarked.present) {
      map['planned_marked'] = Variable<int>(plannedMarked.value);
    }
    if (isWriting.present) {
      map['is_writing'] = Variable<bool>(isWriting.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueRowsCompanion(')
          ..write('id: $id, ')
          ..write('articleId: $articleId, ')
          ..write('state: $state, ')
          ..write('topic: $topic, ')
          ..write('focus: $focus, ')
          ..write('plannedWords: $plannedWords, ')
          ..write('plannedMarked: $plannedMarked, ')
          ..write('isWriting: $isWriting, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $LedgerRowsTable extends LedgerRows
    with TableInfo<$LedgerRowsTable, LedgerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgerRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _articleIdMeta =
      const VerificationMeta('articleId');
  @override
  late final GeneratedColumn<String> articleId = GeneratedColumn<String>(
      'article_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
      'topic', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _readsMeta = const VerificationMeta('reads');
  @override
  late final GeneratedColumn<int> reads = GeneratedColumn<int>(
      'reads', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _listensMeta =
      const VerificationMeta('listens');
  @override
  late final GeneratedColumn<int> listens = GeneratedColumn<int>(
      'listens', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _kilobytesMeta =
      const VerificationMeta('kilobytes');
  @override
  late final GeneratedColumn<int> kilobytes = GeneratedColumn<int>(
      'kilobytes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _freedKilobytesMeta =
      const VerificationMeta('freedKilobytes');
  @override
  late final GeneratedColumn<int> freedKilobytes = GeneratedColumn<int>(
      'freed_kilobytes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _goneReasonMeta =
      const VerificationMeta('goneReason');
  @override
  late final GeneratedColumn<String> goneReason = GeneratedColumn<String>(
      'gone_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        articleId,
        title,
        topic,
        reads,
        listens,
        kilobytes,
        freedKilobytes,
        goneReason
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledger_rows';
  @override
  VerificationContext validateIntegrity(Insertable<LedgerRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('article_id')) {
      context.handle(_articleIdMeta,
          articleId.isAcceptableOrUnknown(data['article_id']!, _articleIdMeta));
    } else if (isInserting) {
      context.missing(_articleIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
          _topicMeta, topic.isAcceptableOrUnknown(data['topic']!, _topicMeta));
    }
    if (data.containsKey('reads')) {
      context.handle(
          _readsMeta, reads.isAcceptableOrUnknown(data['reads']!, _readsMeta));
    }
    if (data.containsKey('listens')) {
      context.handle(_listensMeta,
          listens.isAcceptableOrUnknown(data['listens']!, _listensMeta));
    }
    if (data.containsKey('kilobytes')) {
      context.handle(_kilobytesMeta,
          kilobytes.isAcceptableOrUnknown(data['kilobytes']!, _kilobytesMeta));
    }
    if (data.containsKey('freed_kilobytes')) {
      context.handle(
          _freedKilobytesMeta,
          freedKilobytes.isAcceptableOrUnknown(
              data['freed_kilobytes']!, _freedKilobytesMeta));
    }
    if (data.containsKey('gone_reason')) {
      context.handle(
          _goneReasonMeta,
          goneReason.isAcceptableOrUnknown(
              data['gone_reason']!, _goneReasonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {articleId};
  @override
  LedgerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LedgerRow(
      articleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}article_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      topic: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}topic'])!,
      reads: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reads'])!,
      listens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}listens'])!,
      kilobytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}kilobytes'])!,
      freedKilobytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}freed_kilobytes'])!,
      goneReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}gone_reason']),
    );
  }

  @override
  $LedgerRowsTable createAlias(String alias) {
    return $LedgerRowsTable(attachedDatabase, alias);
  }
}

class LedgerRow extends DataClass implements Insertable<LedgerRow> {
  final String articleId;
  final String title;
  final String topic;
  final int reads;
  final int listens;
  final int kilobytes;
  final int freedKilobytes;
  final String? goneReason;
  const LedgerRow(
      {required this.articleId,
      required this.title,
      required this.topic,
      required this.reads,
      required this.listens,
      required this.kilobytes,
      required this.freedKilobytes,
      this.goneReason});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['article_id'] = Variable<String>(articleId);
    map['title'] = Variable<String>(title);
    map['topic'] = Variable<String>(topic);
    map['reads'] = Variable<int>(reads);
    map['listens'] = Variable<int>(listens);
    map['kilobytes'] = Variable<int>(kilobytes);
    map['freed_kilobytes'] = Variable<int>(freedKilobytes);
    if (!nullToAbsent || goneReason != null) {
      map['gone_reason'] = Variable<String>(goneReason);
    }
    return map;
  }

  LedgerRowsCompanion toCompanion(bool nullToAbsent) {
    return LedgerRowsCompanion(
      articleId: Value(articleId),
      title: Value(title),
      topic: Value(topic),
      reads: Value(reads),
      listens: Value(listens),
      kilobytes: Value(kilobytes),
      freedKilobytes: Value(freedKilobytes),
      goneReason: goneReason == null && nullToAbsent
          ? const Value.absent()
          : Value(goneReason),
    );
  }

  factory LedgerRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LedgerRow(
      articleId: serializer.fromJson<String>(json['articleId']),
      title: serializer.fromJson<String>(json['title']),
      topic: serializer.fromJson<String>(json['topic']),
      reads: serializer.fromJson<int>(json['reads']),
      listens: serializer.fromJson<int>(json['listens']),
      kilobytes: serializer.fromJson<int>(json['kilobytes']),
      freedKilobytes: serializer.fromJson<int>(json['freedKilobytes']),
      goneReason: serializer.fromJson<String?>(json['goneReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'articleId': serializer.toJson<String>(articleId),
      'title': serializer.toJson<String>(title),
      'topic': serializer.toJson<String>(topic),
      'reads': serializer.toJson<int>(reads),
      'listens': serializer.toJson<int>(listens),
      'kilobytes': serializer.toJson<int>(kilobytes),
      'freedKilobytes': serializer.toJson<int>(freedKilobytes),
      'goneReason': serializer.toJson<String?>(goneReason),
    };
  }

  LedgerRow copyWith(
          {String? articleId,
          String? title,
          String? topic,
          int? reads,
          int? listens,
          int? kilobytes,
          int? freedKilobytes,
          Value<String?> goneReason = const Value.absent()}) =>
      LedgerRow(
        articleId: articleId ?? this.articleId,
        title: title ?? this.title,
        topic: topic ?? this.topic,
        reads: reads ?? this.reads,
        listens: listens ?? this.listens,
        kilobytes: kilobytes ?? this.kilobytes,
        freedKilobytes: freedKilobytes ?? this.freedKilobytes,
        goneReason: goneReason.present ? goneReason.value : this.goneReason,
      );
  LedgerRow copyWithCompanion(LedgerRowsCompanion data) {
    return LedgerRow(
      articleId: data.articleId.present ? data.articleId.value : this.articleId,
      title: data.title.present ? data.title.value : this.title,
      topic: data.topic.present ? data.topic.value : this.topic,
      reads: data.reads.present ? data.reads.value : this.reads,
      listens: data.listens.present ? data.listens.value : this.listens,
      kilobytes: data.kilobytes.present ? data.kilobytes.value : this.kilobytes,
      freedKilobytes: data.freedKilobytes.present
          ? data.freedKilobytes.value
          : this.freedKilobytes,
      goneReason:
          data.goneReason.present ? data.goneReason.value : this.goneReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LedgerRow(')
          ..write('articleId: $articleId, ')
          ..write('title: $title, ')
          ..write('topic: $topic, ')
          ..write('reads: $reads, ')
          ..write('listens: $listens, ')
          ..write('kilobytes: $kilobytes, ')
          ..write('freedKilobytes: $freedKilobytes, ')
          ..write('goneReason: $goneReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(articleId, title, topic, reads, listens,
      kilobytes, freedKilobytes, goneReason);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerRow &&
          other.articleId == this.articleId &&
          other.title == this.title &&
          other.topic == this.topic &&
          other.reads == this.reads &&
          other.listens == this.listens &&
          other.kilobytes == this.kilobytes &&
          other.freedKilobytes == this.freedKilobytes &&
          other.goneReason == this.goneReason);
}

class LedgerRowsCompanion extends UpdateCompanion<LedgerRow> {
  final Value<String> articleId;
  final Value<String> title;
  final Value<String> topic;
  final Value<int> reads;
  final Value<int> listens;
  final Value<int> kilobytes;
  final Value<int> freedKilobytes;
  final Value<String?> goneReason;
  final Value<int> rowid;
  const LedgerRowsCompanion({
    this.articleId = const Value.absent(),
    this.title = const Value.absent(),
    this.topic = const Value.absent(),
    this.reads = const Value.absent(),
    this.listens = const Value.absent(),
    this.kilobytes = const Value.absent(),
    this.freedKilobytes = const Value.absent(),
    this.goneReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LedgerRowsCompanion.insert({
    required String articleId,
    required String title,
    this.topic = const Value.absent(),
    this.reads = const Value.absent(),
    this.listens = const Value.absent(),
    this.kilobytes = const Value.absent(),
    this.freedKilobytes = const Value.absent(),
    this.goneReason = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : articleId = Value(articleId),
        title = Value(title);
  static Insertable<LedgerRow> custom({
    Expression<String>? articleId,
    Expression<String>? title,
    Expression<String>? topic,
    Expression<int>? reads,
    Expression<int>? listens,
    Expression<int>? kilobytes,
    Expression<int>? freedKilobytes,
    Expression<String>? goneReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (articleId != null) 'article_id': articleId,
      if (title != null) 'title': title,
      if (topic != null) 'topic': topic,
      if (reads != null) 'reads': reads,
      if (listens != null) 'listens': listens,
      if (kilobytes != null) 'kilobytes': kilobytes,
      if (freedKilobytes != null) 'freed_kilobytes': freedKilobytes,
      if (goneReason != null) 'gone_reason': goneReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LedgerRowsCompanion copyWith(
      {Value<String>? articleId,
      Value<String>? title,
      Value<String>? topic,
      Value<int>? reads,
      Value<int>? listens,
      Value<int>? kilobytes,
      Value<int>? freedKilobytes,
      Value<String?>? goneReason,
      Value<int>? rowid}) {
    return LedgerRowsCompanion(
      articleId: articleId ?? this.articleId,
      title: title ?? this.title,
      topic: topic ?? this.topic,
      reads: reads ?? this.reads,
      listens: listens ?? this.listens,
      kilobytes: kilobytes ?? this.kilobytes,
      freedKilobytes: freedKilobytes ?? this.freedKilobytes,
      goneReason: goneReason ?? this.goneReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (articleId.present) {
      map['article_id'] = Variable<String>(articleId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (reads.present) {
      map['reads'] = Variable<int>(reads.value);
    }
    if (listens.present) {
      map['listens'] = Variable<int>(listens.value);
    }
    if (kilobytes.present) {
      map['kilobytes'] = Variable<int>(kilobytes.value);
    }
    if (freedKilobytes.present) {
      map['freed_kilobytes'] = Variable<int>(freedKilobytes.value);
    }
    if (goneReason.present) {
      map['gone_reason'] = Variable<String>(goneReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgerRowsCompanion(')
          ..write('articleId: $articleId, ')
          ..write('title: $title, ')
          ..write('topic: $topic, ')
          ..write('reads: $reads, ')
          ..write('listens: $listens, ')
          ..write('kilobytes: $kilobytes, ')
          ..write('freedKilobytes: $freedKilobytes, ')
          ..write('goneReason: $goneReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DayLogRowsTable extends DayLogRows
    with TableInfo<$DayLogRowsTable, DayLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DayLogRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
      'day', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _articleIdMeta =
      const VerificationMeta('articleId');
  @override
  late final GeneratedColumn<String> articleId = GeneratedColumn<String>(
      'article_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _readsMeta = const VerificationMeta('reads');
  @override
  late final GeneratedColumn<int> reads = GeneratedColumn<int>(
      'reads', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _listensMeta =
      const VerificationMeta('listens');
  @override
  late final GeneratedColumn<int> listens = GeneratedColumn<int>(
      'listens', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _minutesMeta =
      const VerificationMeta('minutes');
  @override
  late final GeneratedColumn<int> minutes = GeneratedColumn<int>(
      'minutes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [day, articleId, title, reads, listens, minutes];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_log_rows';
  @override
  VerificationContext validateIntegrity(Insertable<DayLogRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
          _dayMeta, day.isAcceptableOrUnknown(data['day']!, _dayMeta));
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('article_id')) {
      context.handle(_articleIdMeta,
          articleId.isAcceptableOrUnknown(data['article_id']!, _articleIdMeta));
    } else if (isInserting) {
      context.missing(_articleIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('reads')) {
      context.handle(
          _readsMeta, reads.isAcceptableOrUnknown(data['reads']!, _readsMeta));
    }
    if (data.containsKey('listens')) {
      context.handle(_listensMeta,
          listens.isAcceptableOrUnknown(data['listens']!, _listensMeta));
    }
    if (data.containsKey('minutes')) {
      context.handle(_minutesMeta,
          minutes.isAcceptableOrUnknown(data['minutes']!, _minutesMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {day, articleId};
  @override
  DayLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DayLogRow(
      day: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}day'])!,
      articleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}article_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      reads: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reads'])!,
      listens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}listens'])!,
      minutes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}minutes'])!,
    );
  }

  @override
  $DayLogRowsTable createAlias(String alias) {
    return $DayLogRowsTable(attachedDatabase, alias);
  }
}

class DayLogRow extends DataClass implements Insertable<DayLogRow> {
  final String day;
  final String articleId;
  final String title;
  final int reads;
  final int listens;
  final int minutes;
  const DayLogRow(
      {required this.day,
      required this.articleId,
      required this.title,
      required this.reads,
      required this.listens,
      required this.minutes});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<String>(day);
    map['article_id'] = Variable<String>(articleId);
    map['title'] = Variable<String>(title);
    map['reads'] = Variable<int>(reads);
    map['listens'] = Variable<int>(listens);
    map['minutes'] = Variable<int>(minutes);
    return map;
  }

  DayLogRowsCompanion toCompanion(bool nullToAbsent) {
    return DayLogRowsCompanion(
      day: Value(day),
      articleId: Value(articleId),
      title: Value(title),
      reads: Value(reads),
      listens: Value(listens),
      minutes: Value(minutes),
    );
  }

  factory DayLogRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DayLogRow(
      day: serializer.fromJson<String>(json['day']),
      articleId: serializer.fromJson<String>(json['articleId']),
      title: serializer.fromJson<String>(json['title']),
      reads: serializer.fromJson<int>(json['reads']),
      listens: serializer.fromJson<int>(json['listens']),
      minutes: serializer.fromJson<int>(json['minutes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<String>(day),
      'articleId': serializer.toJson<String>(articleId),
      'title': serializer.toJson<String>(title),
      'reads': serializer.toJson<int>(reads),
      'listens': serializer.toJson<int>(listens),
      'minutes': serializer.toJson<int>(minutes),
    };
  }

  DayLogRow copyWith(
          {String? day,
          String? articleId,
          String? title,
          int? reads,
          int? listens,
          int? minutes}) =>
      DayLogRow(
        day: day ?? this.day,
        articleId: articleId ?? this.articleId,
        title: title ?? this.title,
        reads: reads ?? this.reads,
        listens: listens ?? this.listens,
        minutes: minutes ?? this.minutes,
      );
  DayLogRow copyWithCompanion(DayLogRowsCompanion data) {
    return DayLogRow(
      day: data.day.present ? data.day.value : this.day,
      articleId: data.articleId.present ? data.articleId.value : this.articleId,
      title: data.title.present ? data.title.value : this.title,
      reads: data.reads.present ? data.reads.value : this.reads,
      listens: data.listens.present ? data.listens.value : this.listens,
      minutes: data.minutes.present ? data.minutes.value : this.minutes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DayLogRow(')
          ..write('day: $day, ')
          ..write('articleId: $articleId, ')
          ..write('title: $title, ')
          ..write('reads: $reads, ')
          ..write('listens: $listens, ')
          ..write('minutes: $minutes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(day, articleId, title, reads, listens, minutes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayLogRow &&
          other.day == this.day &&
          other.articleId == this.articleId &&
          other.title == this.title &&
          other.reads == this.reads &&
          other.listens == this.listens &&
          other.minutes == this.minutes);
}

class DayLogRowsCompanion extends UpdateCompanion<DayLogRow> {
  final Value<String> day;
  final Value<String> articleId;
  final Value<String> title;
  final Value<int> reads;
  final Value<int> listens;
  final Value<int> minutes;
  final Value<int> rowid;
  const DayLogRowsCompanion({
    this.day = const Value.absent(),
    this.articleId = const Value.absent(),
    this.title = const Value.absent(),
    this.reads = const Value.absent(),
    this.listens = const Value.absent(),
    this.minutes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DayLogRowsCompanion.insert({
    required String day,
    required String articleId,
    required String title,
    this.reads = const Value.absent(),
    this.listens = const Value.absent(),
    this.minutes = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : day = Value(day),
        articleId = Value(articleId),
        title = Value(title);
  static Insertable<DayLogRow> custom({
    Expression<String>? day,
    Expression<String>? articleId,
    Expression<String>? title,
    Expression<int>? reads,
    Expression<int>? listens,
    Expression<int>? minutes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (articleId != null) 'article_id': articleId,
      if (title != null) 'title': title,
      if (reads != null) 'reads': reads,
      if (listens != null) 'listens': listens,
      if (minutes != null) 'minutes': minutes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DayLogRowsCompanion copyWith(
      {Value<String>? day,
      Value<String>? articleId,
      Value<String>? title,
      Value<int>? reads,
      Value<int>? listens,
      Value<int>? minutes,
      Value<int>? rowid}) {
    return DayLogRowsCompanion(
      day: day ?? this.day,
      articleId: articleId ?? this.articleId,
      title: title ?? this.title,
      reads: reads ?? this.reads,
      listens: listens ?? this.listens,
      minutes: minutes ?? this.minutes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (articleId.present) {
      map['article_id'] = Variable<String>(articleId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (reads.present) {
      map['reads'] = Variable<int>(reads.value);
    }
    if (listens.present) {
      map['listens'] = Variable<int>(listens.value);
    }
    if (minutes.present) {
      map['minutes'] = Variable<int>(minutes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DayLogRowsCompanion(')
          ..write('day: $day, ')
          ..write('articleId: $articleId, ')
          ..write('title: $title, ')
          ..write('reads: $reads, ')
          ..write('listens: $listens, ')
          ..write('minutes: $minutes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WordRowsTable extends WordRows with TableInfo<$WordRowsTable, WordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WordRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _lemmaMeta = const VerificationMeta('lemma');
  @override
  late final GeneratedColumn<String> lemma = GeneratedColumn<String>(
      'lemma', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _encountersMeta =
      const VerificationMeta('encounters');
  @override
  late final GeneratedColumn<int> encounters = GeneratedColumn<int>(
      'encounters', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _starredMeta =
      const VerificationMeta('starred');
  @override
  late final GeneratedColumn<bool> starred = GeneratedColumn<bool>(
      'starred', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("starred" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _starredAtDayMeta =
      const VerificationMeta('starredAtDay');
  @override
  late final GeneratedColumn<String> starredAtDay = GeneratedColumn<String>(
      'starred_at_day', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMetDayMeta =
      const VerificationMeta('lastMetDay');
  @override
  late final GeneratedColumn<String> lastMetDay = GeneratedColumn<String>(
      'last_met_day', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [lemma, encounters, starred, starredAtDay, lastMetDay];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'word_rows';
  @override
  VerificationContext validateIntegrity(Insertable<WordRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('lemma')) {
      context.handle(
          _lemmaMeta, lemma.isAcceptableOrUnknown(data['lemma']!, _lemmaMeta));
    } else if (isInserting) {
      context.missing(_lemmaMeta);
    }
    if (data.containsKey('encounters')) {
      context.handle(
          _encountersMeta,
          encounters.isAcceptableOrUnknown(
              data['encounters']!, _encountersMeta));
    }
    if (data.containsKey('starred')) {
      context.handle(_starredMeta,
          starred.isAcceptableOrUnknown(data['starred']!, _starredMeta));
    }
    if (data.containsKey('starred_at_day')) {
      context.handle(
          _starredAtDayMeta,
          starredAtDay.isAcceptableOrUnknown(
              data['starred_at_day']!, _starredAtDayMeta));
    }
    if (data.containsKey('last_met_day')) {
      context.handle(
          _lastMetDayMeta,
          lastMetDay.isAcceptableOrUnknown(
              data['last_met_day']!, _lastMetDayMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {lemma};
  @override
  WordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WordRow(
      lemma: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}lemma'])!,
      encounters: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}encounters'])!,
      starred: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}starred'])!,
      starredAtDay: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}starred_at_day']),
      lastMetDay: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_met_day']),
    );
  }

  @override
  $WordRowsTable createAlias(String alias) {
    return $WordRowsTable(attachedDatabase, alias);
  }
}

class WordRow extends DataClass implements Insertable<WordRow> {
  final String lemma;
  final int encounters;
  final bool starred;
  final String? starredAtDay;
  final String? lastMetDay;
  const WordRow(
      {required this.lemma,
      required this.encounters,
      required this.starred,
      this.starredAtDay,
      this.lastMetDay});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['lemma'] = Variable<String>(lemma);
    map['encounters'] = Variable<int>(encounters);
    map['starred'] = Variable<bool>(starred);
    if (!nullToAbsent || starredAtDay != null) {
      map['starred_at_day'] = Variable<String>(starredAtDay);
    }
    if (!nullToAbsent || lastMetDay != null) {
      map['last_met_day'] = Variable<String>(lastMetDay);
    }
    return map;
  }

  WordRowsCompanion toCompanion(bool nullToAbsent) {
    return WordRowsCompanion(
      lemma: Value(lemma),
      encounters: Value(encounters),
      starred: Value(starred),
      starredAtDay: starredAtDay == null && nullToAbsent
          ? const Value.absent()
          : Value(starredAtDay),
      lastMetDay: lastMetDay == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMetDay),
    );
  }

  factory WordRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WordRow(
      lemma: serializer.fromJson<String>(json['lemma']),
      encounters: serializer.fromJson<int>(json['encounters']),
      starred: serializer.fromJson<bool>(json['starred']),
      starredAtDay: serializer.fromJson<String?>(json['starredAtDay']),
      lastMetDay: serializer.fromJson<String?>(json['lastMetDay']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'lemma': serializer.toJson<String>(lemma),
      'encounters': serializer.toJson<int>(encounters),
      'starred': serializer.toJson<bool>(starred),
      'starredAtDay': serializer.toJson<String?>(starredAtDay),
      'lastMetDay': serializer.toJson<String?>(lastMetDay),
    };
  }

  WordRow copyWith(
          {String? lemma,
          int? encounters,
          bool? starred,
          Value<String?> starredAtDay = const Value.absent(),
          Value<String?> lastMetDay = const Value.absent()}) =>
      WordRow(
        lemma: lemma ?? this.lemma,
        encounters: encounters ?? this.encounters,
        starred: starred ?? this.starred,
        starredAtDay:
            starredAtDay.present ? starredAtDay.value : this.starredAtDay,
        lastMetDay: lastMetDay.present ? lastMetDay.value : this.lastMetDay,
      );
  WordRow copyWithCompanion(WordRowsCompanion data) {
    return WordRow(
      lemma: data.lemma.present ? data.lemma.value : this.lemma,
      encounters:
          data.encounters.present ? data.encounters.value : this.encounters,
      starred: data.starred.present ? data.starred.value : this.starred,
      starredAtDay: data.starredAtDay.present
          ? data.starredAtDay.value
          : this.starredAtDay,
      lastMetDay:
          data.lastMetDay.present ? data.lastMetDay.value : this.lastMetDay,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WordRow(')
          ..write('lemma: $lemma, ')
          ..write('encounters: $encounters, ')
          ..write('starred: $starred, ')
          ..write('starredAtDay: $starredAtDay, ')
          ..write('lastMetDay: $lastMetDay')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(lemma, encounters, starred, starredAtDay, lastMetDay);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordRow &&
          other.lemma == this.lemma &&
          other.encounters == this.encounters &&
          other.starred == this.starred &&
          other.starredAtDay == this.starredAtDay &&
          other.lastMetDay == this.lastMetDay);
}

class WordRowsCompanion extends UpdateCompanion<WordRow> {
  final Value<String> lemma;
  final Value<int> encounters;
  final Value<bool> starred;
  final Value<String?> starredAtDay;
  final Value<String?> lastMetDay;
  final Value<int> rowid;
  const WordRowsCompanion({
    this.lemma = const Value.absent(),
    this.encounters = const Value.absent(),
    this.starred = const Value.absent(),
    this.starredAtDay = const Value.absent(),
    this.lastMetDay = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WordRowsCompanion.insert({
    required String lemma,
    this.encounters = const Value.absent(),
    this.starred = const Value.absent(),
    this.starredAtDay = const Value.absent(),
    this.lastMetDay = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : lemma = Value(lemma);
  static Insertable<WordRow> custom({
    Expression<String>? lemma,
    Expression<int>? encounters,
    Expression<bool>? starred,
    Expression<String>? starredAtDay,
    Expression<String>? lastMetDay,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (lemma != null) 'lemma': lemma,
      if (encounters != null) 'encounters': encounters,
      if (starred != null) 'starred': starred,
      if (starredAtDay != null) 'starred_at_day': starredAtDay,
      if (lastMetDay != null) 'last_met_day': lastMetDay,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WordRowsCompanion copyWith(
      {Value<String>? lemma,
      Value<int>? encounters,
      Value<bool>? starred,
      Value<String?>? starredAtDay,
      Value<String?>? lastMetDay,
      Value<int>? rowid}) {
    return WordRowsCompanion(
      lemma: lemma ?? this.lemma,
      encounters: encounters ?? this.encounters,
      starred: starred ?? this.starred,
      starredAtDay: starredAtDay ?? this.starredAtDay,
      lastMetDay: lastMetDay ?? this.lastMetDay,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (lemma.present) {
      map['lemma'] = Variable<String>(lemma.value);
    }
    if (encounters.present) {
      map['encounters'] = Variable<int>(encounters.value);
    }
    if (starred.present) {
      map['starred'] = Variable<bool>(starred.value);
    }
    if (starredAtDay.present) {
      map['starred_at_day'] = Variable<String>(starredAtDay.value);
    }
    if (lastMetDay.present) {
      map['last_met_day'] = Variable<String>(lastMetDay.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WordRowsCompanion(')
          ..write('lemma: $lemma, ')
          ..write('encounters: $encounters, ')
          ..write('starred: $starred, ')
          ..write('starredAtDay: $starredAtDay, ')
          ..write('lastMetDay: $lastMetDay, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanRowsTable extends PlanRows with TableInfo<$PlanRowsTable, PlanRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _readerMeta = const VerificationMeta('reader');
  @override
  late final GeneratedColumn<String> reader = GeneratedColumn<String>(
      'reader', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _topicsMeta = const VerificationMeta('topics');
  @override
  late final GeneratedColumn<String> topics = GeneratedColumn<String>(
      'topics', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _styleMeta = const VerificationMeta('style');
  @override
  late final GeneratedColumn<String> style = GeneratedColumn<String>(
      'style', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _glossMeta = const VerificationMeta('gloss');
  @override
  late final GeneratedColumn<String> gloss = GeneratedColumn<String>(
      'gloss', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _avoidMeta = const VerificationMeta('avoid');
  @override
  late final GeneratedColumn<String> avoid = GeneratedColumn<String>(
      'avoid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _lengthMeta = const VerificationMeta('length');
  @override
  late final GeneratedColumn<int> length = GeneratedColumn<int>(
      'length', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(300));
  static const VerificationMeta _markedMeta = const VerificationMeta('marked');
  @override
  late final GeneratedColumn<int> marked = GeneratedColumn<int>(
      'marked', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(6));
  static const VerificationMeta _rawMeta = const VerificationMeta('raw');
  @override
  late final GeneratedColumn<String> raw = GeneratedColumn<String>(
      'raw', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  @override
  List<GeneratedColumn> get $columns =>
      [id, reader, topics, style, gloss, avoid, length, marked, raw];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_rows';
  @override
  VerificationContext validateIntegrity(Insertable<PlanRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('reader')) {
      context.handle(_readerMeta,
          reader.isAcceptableOrUnknown(data['reader']!, _readerMeta));
    }
    if (data.containsKey('topics')) {
      context.handle(_topicsMeta,
          topics.isAcceptableOrUnknown(data['topics']!, _topicsMeta));
    }
    if (data.containsKey('style')) {
      context.handle(
          _styleMeta, style.isAcceptableOrUnknown(data['style']!, _styleMeta));
    }
    if (data.containsKey('gloss')) {
      context.handle(
          _glossMeta, gloss.isAcceptableOrUnknown(data['gloss']!, _glossMeta));
    }
    if (data.containsKey('avoid')) {
      context.handle(
          _avoidMeta, avoid.isAcceptableOrUnknown(data['avoid']!, _avoidMeta));
    }
    if (data.containsKey('length')) {
      context.handle(_lengthMeta,
          length.isAcceptableOrUnknown(data['length']!, _lengthMeta));
    }
    if (data.containsKey('marked')) {
      context.handle(_markedMeta,
          marked.isAcceptableOrUnknown(data['marked']!, _markedMeta));
    }
    if (data.containsKey('raw')) {
      context.handle(
          _rawMeta, raw.isAcceptableOrUnknown(data['raw']!, _rawMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      reader: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reader'])!,
      topics: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}topics'])!,
      style: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}style'])!,
      gloss: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}gloss'])!,
      avoid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}avoid'])!,
      length: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}length'])!,
      marked: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}marked'])!,
      raw: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}raw'])!,
    );
  }

  @override
  $PlanRowsTable createAlias(String alias) {
    return $PlanRowsTable(attachedDatabase, alias);
  }
}

class PlanRow extends DataClass implements Insertable<PlanRow> {
  final int id;
  final String reader;
  final String topics;
  final String style;
  final String gloss;
  final String avoid;
  final int length;
  final int marked;
  final String raw;
  const PlanRow(
      {required this.id,
      required this.reader,
      required this.topics,
      required this.style,
      required this.gloss,
      required this.avoid,
      required this.length,
      required this.marked,
      required this.raw});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['reader'] = Variable<String>(reader);
    map['topics'] = Variable<String>(topics);
    map['style'] = Variable<String>(style);
    map['gloss'] = Variable<String>(gloss);
    map['avoid'] = Variable<String>(avoid);
    map['length'] = Variable<int>(length);
    map['marked'] = Variable<int>(marked);
    map['raw'] = Variable<String>(raw);
    return map;
  }

  PlanRowsCompanion toCompanion(bool nullToAbsent) {
    return PlanRowsCompanion(
      id: Value(id),
      reader: Value(reader),
      topics: Value(topics),
      style: Value(style),
      gloss: Value(gloss),
      avoid: Value(avoid),
      length: Value(length),
      marked: Value(marked),
      raw: Value(raw),
    );
  }

  factory PlanRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanRow(
      id: serializer.fromJson<int>(json['id']),
      reader: serializer.fromJson<String>(json['reader']),
      topics: serializer.fromJson<String>(json['topics']),
      style: serializer.fromJson<String>(json['style']),
      gloss: serializer.fromJson<String>(json['gloss']),
      avoid: serializer.fromJson<String>(json['avoid']),
      length: serializer.fromJson<int>(json['length']),
      marked: serializer.fromJson<int>(json['marked']),
      raw: serializer.fromJson<String>(json['raw']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'reader': serializer.toJson<String>(reader),
      'topics': serializer.toJson<String>(topics),
      'style': serializer.toJson<String>(style),
      'gloss': serializer.toJson<String>(gloss),
      'avoid': serializer.toJson<String>(avoid),
      'length': serializer.toJson<int>(length),
      'marked': serializer.toJson<int>(marked),
      'raw': serializer.toJson<String>(raw),
    };
  }

  PlanRow copyWith(
          {int? id,
          String? reader,
          String? topics,
          String? style,
          String? gloss,
          String? avoid,
          int? length,
          int? marked,
          String? raw}) =>
      PlanRow(
        id: id ?? this.id,
        reader: reader ?? this.reader,
        topics: topics ?? this.topics,
        style: style ?? this.style,
        gloss: gloss ?? this.gloss,
        avoid: avoid ?? this.avoid,
        length: length ?? this.length,
        marked: marked ?? this.marked,
        raw: raw ?? this.raw,
      );
  PlanRow copyWithCompanion(PlanRowsCompanion data) {
    return PlanRow(
      id: data.id.present ? data.id.value : this.id,
      reader: data.reader.present ? data.reader.value : this.reader,
      topics: data.topics.present ? data.topics.value : this.topics,
      style: data.style.present ? data.style.value : this.style,
      gloss: data.gloss.present ? data.gloss.value : this.gloss,
      avoid: data.avoid.present ? data.avoid.value : this.avoid,
      length: data.length.present ? data.length.value : this.length,
      marked: data.marked.present ? data.marked.value : this.marked,
      raw: data.raw.present ? data.raw.value : this.raw,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanRow(')
          ..write('id: $id, ')
          ..write('reader: $reader, ')
          ..write('topics: $topics, ')
          ..write('style: $style, ')
          ..write('gloss: $gloss, ')
          ..write('avoid: $avoid, ')
          ..write('length: $length, ')
          ..write('marked: $marked, ')
          ..write('raw: $raw')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, reader, topics, style, gloss, avoid, length, marked, raw);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanRow &&
          other.id == this.id &&
          other.reader == this.reader &&
          other.topics == this.topics &&
          other.style == this.style &&
          other.gloss == this.gloss &&
          other.avoid == this.avoid &&
          other.length == this.length &&
          other.marked == this.marked &&
          other.raw == this.raw);
}

class PlanRowsCompanion extends UpdateCompanion<PlanRow> {
  final Value<int> id;
  final Value<String> reader;
  final Value<String> topics;
  final Value<String> style;
  final Value<String> gloss;
  final Value<String> avoid;
  final Value<int> length;
  final Value<int> marked;
  final Value<String> raw;
  const PlanRowsCompanion({
    this.id = const Value.absent(),
    this.reader = const Value.absent(),
    this.topics = const Value.absent(),
    this.style = const Value.absent(),
    this.gloss = const Value.absent(),
    this.avoid = const Value.absent(),
    this.length = const Value.absent(),
    this.marked = const Value.absent(),
    this.raw = const Value.absent(),
  });
  PlanRowsCompanion.insert({
    this.id = const Value.absent(),
    this.reader = const Value.absent(),
    this.topics = const Value.absent(),
    this.style = const Value.absent(),
    this.gloss = const Value.absent(),
    this.avoid = const Value.absent(),
    this.length = const Value.absent(),
    this.marked = const Value.absent(),
    this.raw = const Value.absent(),
  });
  static Insertable<PlanRow> custom({
    Expression<int>? id,
    Expression<String>? reader,
    Expression<String>? topics,
    Expression<String>? style,
    Expression<String>? gloss,
    Expression<String>? avoid,
    Expression<int>? length,
    Expression<int>? marked,
    Expression<String>? raw,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (reader != null) 'reader': reader,
      if (topics != null) 'topics': topics,
      if (style != null) 'style': style,
      if (gloss != null) 'gloss': gloss,
      if (avoid != null) 'avoid': avoid,
      if (length != null) 'length': length,
      if (marked != null) 'marked': marked,
      if (raw != null) 'raw': raw,
    });
  }

  PlanRowsCompanion copyWith(
      {Value<int>? id,
      Value<String>? reader,
      Value<String>? topics,
      Value<String>? style,
      Value<String>? gloss,
      Value<String>? avoid,
      Value<int>? length,
      Value<int>? marked,
      Value<String>? raw}) {
    return PlanRowsCompanion(
      id: id ?? this.id,
      reader: reader ?? this.reader,
      topics: topics ?? this.topics,
      style: style ?? this.style,
      gloss: gloss ?? this.gloss,
      avoid: avoid ?? this.avoid,
      length: length ?? this.length,
      marked: marked ?? this.marked,
      raw: raw ?? this.raw,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (reader.present) {
      map['reader'] = Variable<String>(reader.value);
    }
    if (topics.present) {
      map['topics'] = Variable<String>(topics.value);
    }
    if (style.present) {
      map['style'] = Variable<String>(style.value);
    }
    if (gloss.present) {
      map['gloss'] = Variable<String>(gloss.value);
    }
    if (avoid.present) {
      map['avoid'] = Variable<String>(avoid.value);
    }
    if (length.present) {
      map['length'] = Variable<int>(length.value);
    }
    if (marked.present) {
      map['marked'] = Variable<int>(marked.value);
    }
    if (raw.present) {
      map['raw'] = Variable<String>(raw.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanRowsCompanion(')
          ..write('id: $id, ')
          ..write('reader: $reader, ')
          ..write('topics: $topics, ')
          ..write('style: $style, ')
          ..write('gloss: $gloss, ')
          ..write('avoid: $avoid, ')
          ..write('length: $length, ')
          ..write('marked: $marked, ')
          ..write('raw: $raw')
          ..write(')'))
        .toString();
  }
}

class $PresetRowsTable extends PresetRows
    with TableInfo<$PresetRowsTable, PresetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PresetRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, kind, label, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preset_rows';
  @override
  VerificationContext validateIntegrity(Insertable<PresetRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PresetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PresetRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label'])!,
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
    );
  }

  @override
  $PresetRowsTable createAlias(String alias) {
    return $PresetRowsTable(attachedDatabase, alias);
  }
}

class PresetRow extends DataClass implements Insertable<PresetRow> {
  final int id;
  final String kind;
  final String label;
  final int position;
  const PresetRow(
      {required this.id,
      required this.kind,
      required this.label,
      required this.position});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['label'] = Variable<String>(label);
    map['position'] = Variable<int>(position);
    return map;
  }

  PresetRowsCompanion toCompanion(bool nullToAbsent) {
    return PresetRowsCompanion(
      id: Value(id),
      kind: Value(kind),
      label: Value(label),
      position: Value(position),
    );
  }

  factory PresetRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PresetRow(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      label: serializer.fromJson<String>(json['label']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'label': serializer.toJson<String>(label),
      'position': serializer.toJson<int>(position),
    };
  }

  PresetRow copyWith({int? id, String? kind, String? label, int? position}) =>
      PresetRow(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        label: label ?? this.label,
        position: position ?? this.position,
      );
  PresetRow copyWithCompanion(PresetRowsCompanion data) {
    return PresetRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      label: data.label.present ? data.label.value : this.label,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PresetRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('label: $label, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, kind, label, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PresetRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.label == this.label &&
          other.position == this.position);
}

class PresetRowsCompanion extends UpdateCompanion<PresetRow> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> label;
  final Value<int> position;
  const PresetRowsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.label = const Value.absent(),
    this.position = const Value.absent(),
  });
  PresetRowsCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String label,
    required int position,
  })  : kind = Value(kind),
        label = Value(label),
        position = Value(position);
  static Insertable<PresetRow> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? label,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (label != null) 'label': label,
      if (position != null) 'position': position,
    });
  }

  PresetRowsCompanion copyWith(
      {Value<int>? id,
      Value<String>? kind,
      Value<String>? label,
      Value<int>? position}) {
    return PresetRowsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PresetRowsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('label: $label, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $SettingsRowsTable extends SettingsRows
    with TableInfo<$SettingsRowsTable, SettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings_rows';
  @override
  VerificationContext validateIntegrity(Insertable<SettingsRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingsRow(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $SettingsRowsTable createAlias(String alias) {
    return $SettingsRowsTable(attachedDatabase, alias);
  }
}

class SettingsRow extends DataClass implements Insertable<SettingsRow> {
  final String key;
  final String value;
  const SettingsRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsRowsCompanion toCompanion(bool nullToAbsent) {
    return SettingsRowsCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory SettingsRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingsRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingsRow copyWith({String? key, String? value}) => SettingsRow(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  SettingsRow copyWithCompanion(SettingsRowsCompanion data) {
    return SettingsRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsRowsCompanion extends UpdateCompanion<SettingsRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsRowsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsRowsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<SettingsRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsRowsCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return SettingsRowsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRowsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $QueueRowsTable queueRows = $QueueRowsTable(this);
  late final $LedgerRowsTable ledgerRows = $LedgerRowsTable(this);
  late final $DayLogRowsTable dayLogRows = $DayLogRowsTable(this);
  late final $WordRowsTable wordRows = $WordRowsTable(this);
  late final $PlanRowsTable planRows = $PlanRowsTable(this);
  late final $PresetRowsTable presetRows = $PresetRowsTable(this);
  late final $SettingsRowsTable settingsRows = $SettingsRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        queueRows,
        ledgerRows,
        dayLogRows,
        wordRows,
        planRows,
        presetRows,
        settingsRows
      ];
}

typedef $$QueueRowsTableCreateCompanionBuilder = QueueRowsCompanion Function({
  Value<int> id,
  required String articleId,
  required String state,
  Value<String> topic,
  Value<String> focus,
  Value<int> plannedWords,
  Value<int> plannedMarked,
  Value<bool> isWriting,
  required int position,
});
typedef $$QueueRowsTableUpdateCompanionBuilder = QueueRowsCompanion Function({
  Value<int> id,
  Value<String> articleId,
  Value<String> state,
  Value<String> topic,
  Value<String> focus,
  Value<int> plannedWords,
  Value<int> plannedMarked,
  Value<bool> isWriting,
  Value<int> position,
});

class $$QueueRowsTableFilterComposer
    extends Composer<_$AppDatabase, $QueueRowsTable> {
  $$QueueRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get focus => $composableBuilder(
      column: $table.focus, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get plannedWords => $composableBuilder(
      column: $table.plannedWords, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get plannedMarked => $composableBuilder(
      column: $table.plannedMarked, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isWriting => $composableBuilder(
      column: $table.isWriting, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));
}

class $$QueueRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $QueueRowsTable> {
  $$QueueRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get focus => $composableBuilder(
      column: $table.focus, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get plannedWords => $composableBuilder(
      column: $table.plannedWords,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get plannedMarked => $composableBuilder(
      column: $table.plannedMarked,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isWriting => $composableBuilder(
      column: $table.isWriting, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));
}

class $$QueueRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $QueueRowsTable> {
  $$QueueRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get articleId =>
      $composableBuilder(column: $table.articleId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<String> get focus =>
      $composableBuilder(column: $table.focus, builder: (column) => column);

  GeneratedColumn<int> get plannedWords => $composableBuilder(
      column: $table.plannedWords, builder: (column) => column);

  GeneratedColumn<int> get plannedMarked => $composableBuilder(
      column: $table.plannedMarked, builder: (column) => column);

  GeneratedColumn<bool> get isWriting =>
      $composableBuilder(column: $table.isWriting, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$QueueRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $QueueRowsTable,
    QueueRow,
    $$QueueRowsTableFilterComposer,
    $$QueueRowsTableOrderingComposer,
    $$QueueRowsTableAnnotationComposer,
    $$QueueRowsTableCreateCompanionBuilder,
    $$QueueRowsTableUpdateCompanionBuilder,
    (QueueRow, BaseReferences<_$AppDatabase, $QueueRowsTable, QueueRow>),
    QueueRow,
    PrefetchHooks Function()> {
  $$QueueRowsTableTableManager(_$AppDatabase db, $QueueRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> articleId = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<String> topic = const Value.absent(),
            Value<String> focus = const Value.absent(),
            Value<int> plannedWords = const Value.absent(),
            Value<int> plannedMarked = const Value.absent(),
            Value<bool> isWriting = const Value.absent(),
            Value<int> position = const Value.absent(),
          }) =>
              QueueRowsCompanion(
            id: id,
            articleId: articleId,
            state: state,
            topic: topic,
            focus: focus,
            plannedWords: plannedWords,
            plannedMarked: plannedMarked,
            isWriting: isWriting,
            position: position,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String articleId,
            required String state,
            Value<String> topic = const Value.absent(),
            Value<String> focus = const Value.absent(),
            Value<int> plannedWords = const Value.absent(),
            Value<int> plannedMarked = const Value.absent(),
            Value<bool> isWriting = const Value.absent(),
            required int position,
          }) =>
              QueueRowsCompanion.insert(
            id: id,
            articleId: articleId,
            state: state,
            topic: topic,
            focus: focus,
            plannedWords: plannedWords,
            plannedMarked: plannedMarked,
            isWriting: isWriting,
            position: position,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$QueueRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $QueueRowsTable,
    QueueRow,
    $$QueueRowsTableFilterComposer,
    $$QueueRowsTableOrderingComposer,
    $$QueueRowsTableAnnotationComposer,
    $$QueueRowsTableCreateCompanionBuilder,
    $$QueueRowsTableUpdateCompanionBuilder,
    (QueueRow, BaseReferences<_$AppDatabase, $QueueRowsTable, QueueRow>),
    QueueRow,
    PrefetchHooks Function()>;
typedef $$LedgerRowsTableCreateCompanionBuilder = LedgerRowsCompanion Function({
  required String articleId,
  required String title,
  Value<String> topic,
  Value<int> reads,
  Value<int> listens,
  Value<int> kilobytes,
  Value<int> freedKilobytes,
  Value<String?> goneReason,
  Value<int> rowid,
});
typedef $$LedgerRowsTableUpdateCompanionBuilder = LedgerRowsCompanion Function({
  Value<String> articleId,
  Value<String> title,
  Value<String> topic,
  Value<int> reads,
  Value<int> listens,
  Value<int> kilobytes,
  Value<int> freedKilobytes,
  Value<String?> goneReason,
  Value<int> rowid,
});

class $$LedgerRowsTableFilterComposer
    extends Composer<_$AppDatabase, $LedgerRowsTable> {
  $$LedgerRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get reads => $composableBuilder(
      column: $table.reads, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get listens => $composableBuilder(
      column: $table.listens, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get kilobytes => $composableBuilder(
      column: $table.kilobytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get freedKilobytes => $composableBuilder(
      column: $table.freedKilobytes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get goneReason => $composableBuilder(
      column: $table.goneReason, builder: (column) => ColumnFilters(column));
}

class $$LedgerRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $LedgerRowsTable> {
  $$LedgerRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get reads => $composableBuilder(
      column: $table.reads, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get listens => $composableBuilder(
      column: $table.listens, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get kilobytes => $composableBuilder(
      column: $table.kilobytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get freedKilobytes => $composableBuilder(
      column: $table.freedKilobytes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get goneReason => $composableBuilder(
      column: $table.goneReason, builder: (column) => ColumnOrderings(column));
}

class $$LedgerRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LedgerRowsTable> {
  $$LedgerRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get articleId =>
      $composableBuilder(column: $table.articleId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<int> get reads =>
      $composableBuilder(column: $table.reads, builder: (column) => column);

  GeneratedColumn<int> get listens =>
      $composableBuilder(column: $table.listens, builder: (column) => column);

  GeneratedColumn<int> get kilobytes =>
      $composableBuilder(column: $table.kilobytes, builder: (column) => column);

  GeneratedColumn<int> get freedKilobytes => $composableBuilder(
      column: $table.freedKilobytes, builder: (column) => column);

  GeneratedColumn<String> get goneReason => $composableBuilder(
      column: $table.goneReason, builder: (column) => column);
}

class $$LedgerRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LedgerRowsTable,
    LedgerRow,
    $$LedgerRowsTableFilterComposer,
    $$LedgerRowsTableOrderingComposer,
    $$LedgerRowsTableAnnotationComposer,
    $$LedgerRowsTableCreateCompanionBuilder,
    $$LedgerRowsTableUpdateCompanionBuilder,
    (LedgerRow, BaseReferences<_$AppDatabase, $LedgerRowsTable, LedgerRow>),
    LedgerRow,
    PrefetchHooks Function()> {
  $$LedgerRowsTableTableManager(_$AppDatabase db, $LedgerRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LedgerRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LedgerRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LedgerRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> articleId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> topic = const Value.absent(),
            Value<int> reads = const Value.absent(),
            Value<int> listens = const Value.absent(),
            Value<int> kilobytes = const Value.absent(),
            Value<int> freedKilobytes = const Value.absent(),
            Value<String?> goneReason = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LedgerRowsCompanion(
            articleId: articleId,
            title: title,
            topic: topic,
            reads: reads,
            listens: listens,
            kilobytes: kilobytes,
            freedKilobytes: freedKilobytes,
            goneReason: goneReason,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String articleId,
            required String title,
            Value<String> topic = const Value.absent(),
            Value<int> reads = const Value.absent(),
            Value<int> listens = const Value.absent(),
            Value<int> kilobytes = const Value.absent(),
            Value<int> freedKilobytes = const Value.absent(),
            Value<String?> goneReason = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LedgerRowsCompanion.insert(
            articleId: articleId,
            title: title,
            topic: topic,
            reads: reads,
            listens: listens,
            kilobytes: kilobytes,
            freedKilobytes: freedKilobytes,
            goneReason: goneReason,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LedgerRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LedgerRowsTable,
    LedgerRow,
    $$LedgerRowsTableFilterComposer,
    $$LedgerRowsTableOrderingComposer,
    $$LedgerRowsTableAnnotationComposer,
    $$LedgerRowsTableCreateCompanionBuilder,
    $$LedgerRowsTableUpdateCompanionBuilder,
    (LedgerRow, BaseReferences<_$AppDatabase, $LedgerRowsTable, LedgerRow>),
    LedgerRow,
    PrefetchHooks Function()>;
typedef $$DayLogRowsTableCreateCompanionBuilder = DayLogRowsCompanion Function({
  required String day,
  required String articleId,
  required String title,
  Value<int> reads,
  Value<int> listens,
  Value<int> minutes,
  Value<int> rowid,
});
typedef $$DayLogRowsTableUpdateCompanionBuilder = DayLogRowsCompanion Function({
  Value<String> day,
  Value<String> articleId,
  Value<String> title,
  Value<int> reads,
  Value<int> listens,
  Value<int> minutes,
  Value<int> rowid,
});

class $$DayLogRowsTableFilterComposer
    extends Composer<_$AppDatabase, $DayLogRowsTable> {
  $$DayLogRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get day => $composableBuilder(
      column: $table.day, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get reads => $composableBuilder(
      column: $table.reads, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get listens => $composableBuilder(
      column: $table.listens, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get minutes => $composableBuilder(
      column: $table.minutes, builder: (column) => ColumnFilters(column));
}

class $$DayLogRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $DayLogRowsTable> {
  $$DayLogRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get day => $composableBuilder(
      column: $table.day, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get reads => $composableBuilder(
      column: $table.reads, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get listens => $composableBuilder(
      column: $table.listens, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get minutes => $composableBuilder(
      column: $table.minutes, builder: (column) => ColumnOrderings(column));
}

class $$DayLogRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DayLogRowsTable> {
  $$DayLogRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get articleId =>
      $composableBuilder(column: $table.articleId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get reads =>
      $composableBuilder(column: $table.reads, builder: (column) => column);

  GeneratedColumn<int> get listens =>
      $composableBuilder(column: $table.listens, builder: (column) => column);

  GeneratedColumn<int> get minutes =>
      $composableBuilder(column: $table.minutes, builder: (column) => column);
}

class $$DayLogRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DayLogRowsTable,
    DayLogRow,
    $$DayLogRowsTableFilterComposer,
    $$DayLogRowsTableOrderingComposer,
    $$DayLogRowsTableAnnotationComposer,
    $$DayLogRowsTableCreateCompanionBuilder,
    $$DayLogRowsTableUpdateCompanionBuilder,
    (DayLogRow, BaseReferences<_$AppDatabase, $DayLogRowsTable, DayLogRow>),
    DayLogRow,
    PrefetchHooks Function()> {
  $$DayLogRowsTableTableManager(_$AppDatabase db, $DayLogRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DayLogRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DayLogRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DayLogRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> day = const Value.absent(),
            Value<String> articleId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> reads = const Value.absent(),
            Value<int> listens = const Value.absent(),
            Value<int> minutes = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DayLogRowsCompanion(
            day: day,
            articleId: articleId,
            title: title,
            reads: reads,
            listens: listens,
            minutes: minutes,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String day,
            required String articleId,
            required String title,
            Value<int> reads = const Value.absent(),
            Value<int> listens = const Value.absent(),
            Value<int> minutes = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DayLogRowsCompanion.insert(
            day: day,
            articleId: articleId,
            title: title,
            reads: reads,
            listens: listens,
            minutes: minutes,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DayLogRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DayLogRowsTable,
    DayLogRow,
    $$DayLogRowsTableFilterComposer,
    $$DayLogRowsTableOrderingComposer,
    $$DayLogRowsTableAnnotationComposer,
    $$DayLogRowsTableCreateCompanionBuilder,
    $$DayLogRowsTableUpdateCompanionBuilder,
    (DayLogRow, BaseReferences<_$AppDatabase, $DayLogRowsTable, DayLogRow>),
    DayLogRow,
    PrefetchHooks Function()>;
typedef $$WordRowsTableCreateCompanionBuilder = WordRowsCompanion Function({
  required String lemma,
  Value<int> encounters,
  Value<bool> starred,
  Value<String?> starredAtDay,
  Value<String?> lastMetDay,
  Value<int> rowid,
});
typedef $$WordRowsTableUpdateCompanionBuilder = WordRowsCompanion Function({
  Value<String> lemma,
  Value<int> encounters,
  Value<bool> starred,
  Value<String?> starredAtDay,
  Value<String?> lastMetDay,
  Value<int> rowid,
});

class $$WordRowsTableFilterComposer
    extends Composer<_$AppDatabase, $WordRowsTable> {
  $$WordRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get lemma => $composableBuilder(
      column: $table.lemma, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get encounters => $composableBuilder(
      column: $table.encounters, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get starred => $composableBuilder(
      column: $table.starred, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get starredAtDay => $composableBuilder(
      column: $table.starredAtDay, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMetDay => $composableBuilder(
      column: $table.lastMetDay, builder: (column) => ColumnFilters(column));
}

class $$WordRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $WordRowsTable> {
  $$WordRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get lemma => $composableBuilder(
      column: $table.lemma, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get encounters => $composableBuilder(
      column: $table.encounters, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get starred => $composableBuilder(
      column: $table.starred, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get starredAtDay => $composableBuilder(
      column: $table.starredAtDay,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMetDay => $composableBuilder(
      column: $table.lastMetDay, builder: (column) => ColumnOrderings(column));
}

class $$WordRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WordRowsTable> {
  $$WordRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get lemma =>
      $composableBuilder(column: $table.lemma, builder: (column) => column);

  GeneratedColumn<int> get encounters => $composableBuilder(
      column: $table.encounters, builder: (column) => column);

  GeneratedColumn<bool> get starred =>
      $composableBuilder(column: $table.starred, builder: (column) => column);

  GeneratedColumn<String> get starredAtDay => $composableBuilder(
      column: $table.starredAtDay, builder: (column) => column);

  GeneratedColumn<String> get lastMetDay => $composableBuilder(
      column: $table.lastMetDay, builder: (column) => column);
}

class $$WordRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $WordRowsTable,
    WordRow,
    $$WordRowsTableFilterComposer,
    $$WordRowsTableOrderingComposer,
    $$WordRowsTableAnnotationComposer,
    $$WordRowsTableCreateCompanionBuilder,
    $$WordRowsTableUpdateCompanionBuilder,
    (WordRow, BaseReferences<_$AppDatabase, $WordRowsTable, WordRow>),
    WordRow,
    PrefetchHooks Function()> {
  $$WordRowsTableTableManager(_$AppDatabase db, $WordRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WordRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WordRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WordRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> lemma = const Value.absent(),
            Value<int> encounters = const Value.absent(),
            Value<bool> starred = const Value.absent(),
            Value<String?> starredAtDay = const Value.absent(),
            Value<String?> lastMetDay = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WordRowsCompanion(
            lemma: lemma,
            encounters: encounters,
            starred: starred,
            starredAtDay: starredAtDay,
            lastMetDay: lastMetDay,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String lemma,
            Value<int> encounters = const Value.absent(),
            Value<bool> starred = const Value.absent(),
            Value<String?> starredAtDay = const Value.absent(),
            Value<String?> lastMetDay = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WordRowsCompanion.insert(
            lemma: lemma,
            encounters: encounters,
            starred: starred,
            starredAtDay: starredAtDay,
            lastMetDay: lastMetDay,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WordRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $WordRowsTable,
    WordRow,
    $$WordRowsTableFilterComposer,
    $$WordRowsTableOrderingComposer,
    $$WordRowsTableAnnotationComposer,
    $$WordRowsTableCreateCompanionBuilder,
    $$WordRowsTableUpdateCompanionBuilder,
    (WordRow, BaseReferences<_$AppDatabase, $WordRowsTable, WordRow>),
    WordRow,
    PrefetchHooks Function()>;
typedef $$PlanRowsTableCreateCompanionBuilder = PlanRowsCompanion Function({
  Value<int> id,
  Value<String> reader,
  Value<String> topics,
  Value<String> style,
  Value<String> gloss,
  Value<String> avoid,
  Value<int> length,
  Value<int> marked,
  Value<String> raw,
});
typedef $$PlanRowsTableUpdateCompanionBuilder = PlanRowsCompanion Function({
  Value<int> id,
  Value<String> reader,
  Value<String> topics,
  Value<String> style,
  Value<String> gloss,
  Value<String> avoid,
  Value<int> length,
  Value<int> marked,
  Value<String> raw,
});

class $$PlanRowsTableFilterComposer
    extends Composer<_$AppDatabase, $PlanRowsTable> {
  $$PlanRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reader => $composableBuilder(
      column: $table.reader, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get topics => $composableBuilder(
      column: $table.topics, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get style => $composableBuilder(
      column: $table.style, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get gloss => $composableBuilder(
      column: $table.gloss, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get avoid => $composableBuilder(
      column: $table.avoid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get length => $composableBuilder(
      column: $table.length, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get marked => $composableBuilder(
      column: $table.marked, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get raw => $composableBuilder(
      column: $table.raw, builder: (column) => ColumnFilters(column));
}

class $$PlanRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanRowsTable> {
  $$PlanRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reader => $composableBuilder(
      column: $table.reader, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get topics => $composableBuilder(
      column: $table.topics, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get style => $composableBuilder(
      column: $table.style, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get gloss => $composableBuilder(
      column: $table.gloss, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get avoid => $composableBuilder(
      column: $table.avoid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get length => $composableBuilder(
      column: $table.length, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get marked => $composableBuilder(
      column: $table.marked, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get raw => $composableBuilder(
      column: $table.raw, builder: (column) => ColumnOrderings(column));
}

class $$PlanRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanRowsTable> {
  $$PlanRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get reader =>
      $composableBuilder(column: $table.reader, builder: (column) => column);

  GeneratedColumn<String> get topics =>
      $composableBuilder(column: $table.topics, builder: (column) => column);

  GeneratedColumn<String> get style =>
      $composableBuilder(column: $table.style, builder: (column) => column);

  GeneratedColumn<String> get gloss =>
      $composableBuilder(column: $table.gloss, builder: (column) => column);

  GeneratedColumn<String> get avoid =>
      $composableBuilder(column: $table.avoid, builder: (column) => column);

  GeneratedColumn<int> get length =>
      $composableBuilder(column: $table.length, builder: (column) => column);

  GeneratedColumn<int> get marked =>
      $composableBuilder(column: $table.marked, builder: (column) => column);

  GeneratedColumn<String> get raw =>
      $composableBuilder(column: $table.raw, builder: (column) => column);
}

class $$PlanRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlanRowsTable,
    PlanRow,
    $$PlanRowsTableFilterComposer,
    $$PlanRowsTableOrderingComposer,
    $$PlanRowsTableAnnotationComposer,
    $$PlanRowsTableCreateCompanionBuilder,
    $$PlanRowsTableUpdateCompanionBuilder,
    (PlanRow, BaseReferences<_$AppDatabase, $PlanRowsTable, PlanRow>),
    PlanRow,
    PrefetchHooks Function()> {
  $$PlanRowsTableTableManager(_$AppDatabase db, $PlanRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> reader = const Value.absent(),
            Value<String> topics = const Value.absent(),
            Value<String> style = const Value.absent(),
            Value<String> gloss = const Value.absent(),
            Value<String> avoid = const Value.absent(),
            Value<int> length = const Value.absent(),
            Value<int> marked = const Value.absent(),
            Value<String> raw = const Value.absent(),
          }) =>
              PlanRowsCompanion(
            id: id,
            reader: reader,
            topics: topics,
            style: style,
            gloss: gloss,
            avoid: avoid,
            length: length,
            marked: marked,
            raw: raw,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> reader = const Value.absent(),
            Value<String> topics = const Value.absent(),
            Value<String> style = const Value.absent(),
            Value<String> gloss = const Value.absent(),
            Value<String> avoid = const Value.absent(),
            Value<int> length = const Value.absent(),
            Value<int> marked = const Value.absent(),
            Value<String> raw = const Value.absent(),
          }) =>
              PlanRowsCompanion.insert(
            id: id,
            reader: reader,
            topics: topics,
            style: style,
            gloss: gloss,
            avoid: avoid,
            length: length,
            marked: marked,
            raw: raw,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PlanRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlanRowsTable,
    PlanRow,
    $$PlanRowsTableFilterComposer,
    $$PlanRowsTableOrderingComposer,
    $$PlanRowsTableAnnotationComposer,
    $$PlanRowsTableCreateCompanionBuilder,
    $$PlanRowsTableUpdateCompanionBuilder,
    (PlanRow, BaseReferences<_$AppDatabase, $PlanRowsTable, PlanRow>),
    PlanRow,
    PrefetchHooks Function()>;
typedef $$PresetRowsTableCreateCompanionBuilder = PresetRowsCompanion Function({
  Value<int> id,
  required String kind,
  required String label,
  required int position,
});
typedef $$PresetRowsTableUpdateCompanionBuilder = PresetRowsCompanion Function({
  Value<int> id,
  Value<String> kind,
  Value<String> label,
  Value<int> position,
});

class $$PresetRowsTableFilterComposer
    extends Composer<_$AppDatabase, $PresetRowsTable> {
  $$PresetRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));
}

class $$PresetRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $PresetRowsTable> {
  $$PresetRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));
}

class $$PresetRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PresetRowsTable> {
  $$PresetRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$PresetRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PresetRowsTable,
    PresetRow,
    $$PresetRowsTableFilterComposer,
    $$PresetRowsTableOrderingComposer,
    $$PresetRowsTableAnnotationComposer,
    $$PresetRowsTableCreateCompanionBuilder,
    $$PresetRowsTableUpdateCompanionBuilder,
    (PresetRow, BaseReferences<_$AppDatabase, $PresetRowsTable, PresetRow>),
    PresetRow,
    PrefetchHooks Function()> {
  $$PresetRowsTableTableManager(_$AppDatabase db, $PresetRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PresetRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PresetRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PresetRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> label = const Value.absent(),
            Value<int> position = const Value.absent(),
          }) =>
              PresetRowsCompanion(
            id: id,
            kind: kind,
            label: label,
            position: position,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String kind,
            required String label,
            required int position,
          }) =>
              PresetRowsCompanion.insert(
            id: id,
            kind: kind,
            label: label,
            position: position,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PresetRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PresetRowsTable,
    PresetRow,
    $$PresetRowsTableFilterComposer,
    $$PresetRowsTableOrderingComposer,
    $$PresetRowsTableAnnotationComposer,
    $$PresetRowsTableCreateCompanionBuilder,
    $$PresetRowsTableUpdateCompanionBuilder,
    (PresetRow, BaseReferences<_$AppDatabase, $PresetRowsTable, PresetRow>),
    PresetRow,
    PrefetchHooks Function()>;
typedef $$SettingsRowsTableCreateCompanionBuilder = SettingsRowsCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsRowsTableUpdateCompanionBuilder = SettingsRowsCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsRowsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsRowsTable> {
  $$SettingsRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$SettingsRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsRowsTable> {
  $$SettingsRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$SettingsRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsRowsTable> {
  $$SettingsRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SettingsRowsTable,
    SettingsRow,
    $$SettingsRowsTableFilterComposer,
    $$SettingsRowsTableOrderingComposer,
    $$SettingsRowsTableAnnotationComposer,
    $$SettingsRowsTableCreateCompanionBuilder,
    $$SettingsRowsTableUpdateCompanionBuilder,
    (
      SettingsRow,
      BaseReferences<_$AppDatabase, $SettingsRowsTable, SettingsRow>
    ),
    SettingsRow,
    PrefetchHooks Function()> {
  $$SettingsRowsTableTableManager(_$AppDatabase db, $SettingsRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SettingsRowsCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              SettingsRowsCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SettingsRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SettingsRowsTable,
    SettingsRow,
    $$SettingsRowsTableFilterComposer,
    $$SettingsRowsTableOrderingComposer,
    $$SettingsRowsTableAnnotationComposer,
    $$SettingsRowsTableCreateCompanionBuilder,
    $$SettingsRowsTableUpdateCompanionBuilder,
    (
      SettingsRow,
      BaseReferences<_$AppDatabase, $SettingsRowsTable, SettingsRow>
    ),
    SettingsRow,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$QueueRowsTableTableManager get queueRows =>
      $$QueueRowsTableTableManager(_db, _db.queueRows);
  $$LedgerRowsTableTableManager get ledgerRows =>
      $$LedgerRowsTableTableManager(_db, _db.ledgerRows);
  $$DayLogRowsTableTableManager get dayLogRows =>
      $$DayLogRowsTableTableManager(_db, _db.dayLogRows);
  $$WordRowsTableTableManager get wordRows =>
      $$WordRowsTableTableManager(_db, _db.wordRows);
  $$PlanRowsTableTableManager get planRows =>
      $$PlanRowsTableTableManager(_db, _db.planRows);
  $$PresetRowsTableTableManager get presetRows =>
      $$PresetRowsTableTableManager(_db, _db.presetRows);
  $$SettingsRowsTableTableManager get settingsRows =>
      $$SettingsRowsTableTableManager(_db, _db.settingsRows);
}
