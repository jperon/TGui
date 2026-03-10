(function() {
  // Test de conversion Int vers Sequence via l'interface utilisateur

  // Ce test vérifie que la conversion d'un champ Int en Sequence
  // préserve les valeurs existantes et configure correctement la séquence

  // Utiliser le framework de test existant
  var R,
    indexOf = [].indexOf;

  R = require('tests.runner');

  describe('Conversion Int vers Sequence (UI)', function() {
    beforeEach(function() {
      // Créer un espace de test avec un champ Int
      this.space = R.test.spaces.create_user_space('test_int_seq_ui', 'Test UI conversion');
      this.field = R.test.spaces.add_field(this.space.id, 'test_id', 'Int', true, 'Test ID');
      
      // Insérer des enregistrements avec des valeurs spécifiques
      R.test.spaces.insert_record(this.space.id, {
        test_id: 100,
        name: 'Test A'
      });
      R.test.spaces.insert_record(this.space.id, {
        test_id: 250,
        name: 'Test B'
      });
      return R.test.spaces.insert_record(this.space.id, {
        test_id: 75,
        name: 'Test C'
      });
    });
    afterEach(function() {
      // Nettoyer
      return R.test.spaces.delete_user_space('test_int_seq_ui');
    });
    it('préserve les valeurs existantes lors de la conversion Int → Sequence', function() {
      var changed, ids, new_record, parsed, records;
      // Convertir le champ en Sequence
      changed = R.test.spaces.change_field_type(this.field.id, 'Sequence', null, 'lua');
      R.eq('Sequence', changed.fieldType);
      
      // Vérifier que les valeurs existantes sont préservées
      records = R.test.spaces.list_records(this.space.id);
      ids = records.map(function(r) {
        return JSON.parse(r.data).test_id;
      });
      
      // Les valeurs originales doivent être préservées
      R.assert(indexOf.call(ids, 100) >= 0, "La valeur 100 devrait être préservée");
      R.assert(indexOf.call(ids, 250) >= 0, "La valeur 250 devrait être préservée");
      R.assert(indexOf.call(ids, 75) >= 0, "La valeur 75 devrait être préservée");
      
      // Insérer un nouvel enregistrement sans valeur pour le champ
      new_record = R.test.spaces.insert_record(this.space.id, {
        name: 'Test D'
      });
      parsed = JSON.parse(new_record.data);
      
      // Le nouvel enregistrement devrait avoir une valeur de séquence
      // La séquence devrait commencer après la valeur max (250)
      return R.eq(251, parsed.test_id);
    });
    return it('gère correctement les champs sans valeur existante', function() {
      var changed, no_id_record, parsed, records;
      // Ajouter un enregistrement sans valeur pour le champ test_id
      R.test.spaces.insert_record(this.space.id, {
        name: 'Test No ID'
      });
      
      // Convertir le champ en Sequence
      changed = R.test.spaces.change_field_type(this.field.id, 'Sequence', null, 'lua');
      R.eq('Sequence', changed.fieldType);
      
      // Vérifier que l'enregistrement sans ID a reçu une valeur de séquence
      records = R.test.spaces.list_records(this.space.id);
      no_id_record = records.find(function(r) {
        return JSON.parse(r.data).name === 'Test No ID';
      });
      parsed = JSON.parse(no_id_record.data);
      
      // Devrait avoir une valeur de séquence (commence à 1 car max_val = 0)
      return R.assert(parsed.test_id >= 1, "L'enregistrement sans ID devrait avoir reçu une valeur de séquence");
    });
  });

}).call(this);
