-- ══════════════════════════════════════════════════════════════════════
-- 68 — La fusion de contacts recolle les profils de dossier Jules — BLOC 2/3 — APPLY (transactionnel)
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/68_fusion_recolle_jules_2_apply.sql
--
-- Problème (relecture Jules app, 20/11) : public.fusionner_contacts ne déplaçait pas jules.profils_mission.crm_contact_id
-- (colonne ajoutée par la migration Jules 257, clé étrangère « on delete set null »). À la mise en corbeille du doublon,
-- le profil du dossier perdait sa fiche en silence, et la liste d'appels pouvait en recréer une (garde Jules 286).
--
-- Ce bloc remplace, à partir de la version en prod le 20/11 (empreintes vérifiées en A0) :
--   · public.fusionner_contacts : recolle jules.profils_mission vers la fiche gardée (avant la corbeille), le note dans
--     « deplaces » (de quoi défaire), signale un dossier qui aurait alors deux profils sur la même fiche ;
--   · public._fusion_defaire    : restaurer_fiche d'une fusion rend aussi ces profils au doublon ;
--   · public._fusion_photo      : la photo d'avant fusion liste les profils reliés.
-- Droits inchangés (create or replace garde les GRANT) : fusionner_contacts exécutable par authenticated et
-- service_role, les deux internes non. Toutes restent SECURITY DEFINER, search_path fixé.
-- Aucune donnée réécrite : diagnostic du 20/11 = 0 profil orphelin, aucune fusion passée n'avait de profil relié.
-- Rejouable : les fonctions sont remplacées à l'identique.
-- ══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on
begin;

-- A0. Garde de dérive : chaque fonction doit être soit la version du 20/11 (avant 68), soit déjà la 68.
do $$
declare r record; v_attendu text;
begin
  for r in select proname, md5(prosrc) h, prosrc ~ 'db/68' deja from pg_proc
            where pronamespace = 'public'::regnamespace and proname in ('fusionner_contacts','_fusion_photo','_fusion_defaire') loop
    v_attendu := case r.proname when 'fusionner_contacts' then '8a04a9bf25f9f50d8389eea6c008fa8f'
                                when '_fusion_photo'      then '8783cfebd9edd79e081fc8e232d96b32'
                                when '_fusion_defaire'    then '03d8a9d222ea9e997a03651c339bd8b2' end;
    if not r.deja and r.h <> v_attendu then
      raise exception 'ARRÊT db/68 : % a changé depuis le 20/11 (md5 %). Repartir de la version en prod.', r.proname, r.h;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'public.fusionner_contacts(bigint,bigint,text,text)', 'execute') then
    raise exception 'ARRÊT db/68 : fusionner_contacts n''est déjà plus exécutable par authenticated (état inattendu).';
  end if;
end $$;

CREATE OR REPLACE FUNCTION public.fusionner_contacts(p_garde bigint, p_doublon bigint, p_origine text DEFAULT 'app'::text, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_origine text := lower(trim(coalesce(p_origine, 'app')));
  v_motif   text := nullif(trim(coalesce(p_motif, '')), '');
  v_uid uuid; v_nom text; v_role text;
  g public.contacts%rowtype;
  d public.contacts%rowtype;
  v_lib_g text; v_lib_d text;
  v_mail_g text; v_mail_d text;
  v_critere text;
  v_compte bigint;
  v_n int;
  v_photo jsonb;
  v_dep jsonb := '{}'::jsonb;        -- ce qui a été déplacé (de quoi le défaire)
  v_x jsonb;
  v_supp_interco jsonb := '[]'::jsonb;
  v_supp_partner jsonb := '[]'::jsonb;
  v_champs jsonb := '{}'::jsonb;
  v_gj jsonb; v_dj jsonb;
  v_col text;
  v_signaux text[] := '{}';
  v_res jsonb;
  v_arch bigint;
  v_trace int;
  v_liens jsonb;
  v_comptes jsonb := '{}'::jsonb;
  v_laisses jsonb := '{}'::jsonb;
  v_k text;
  v_resume text;
begin
  -- a. Appelant (même contrôle que supprimer_fiche) : admin, ou clé service avec origine jules / builder.
  if v_origine not in ('app','mcp','jules','builder') then
    raise exception 'Fusion refusée : origine « % » inconnue (app, mcp, jules, builder).', p_origine using errcode = 'P0001';
  end if;
  select a.o_uid, a.o_nom, a.o_role into v_uid, v_nom, v_role from public._corbeille_appelant(v_origine) a;
  if v_role is distinct from 'admin' then
    raise exception 'Fusion refusée : réservée à un admin (ou à Jules avec la clé service). Signale le doublon à Nicolas.' using errcode = 'P0001';
  end if;

  if p_garde is null or p_doublon is null then
    raise exception 'Fusion refusée : il faut l''id de la fiche gardée ET celui du doublon.' using errcode = 'P0001';
  end if;
  if p_garde = p_doublon then
    raise exception 'Fusion refusée : la fiche gardée et le doublon sont la même fiche (%).', p_garde using errcode = 'P0001';
  end if;

  -- Les deux fiches verrouillées (toujours dans le même ordre : pas d'interblocage entre deux fusions croisées).
  perform 1 from public.contacts where id in (p_garde, p_doublon) order by id for update;
  select * into g from public.contacts where id = p_garde;
  if not found then
    raise exception 'Fusion refusée : la fiche gardée % est introuvable (supprimée ou déjà fusionnée ?).', p_garde using errcode = 'P0001';
  end if;
  select * into d from public.contacts where id = p_doublon;
  if not found then
    raise exception 'Fusion refusée : le doublon % est introuvable (supprimé ou déjà fusionné ?).', p_doublon using errcode = 'P0001';
  end if;
  v_lib_g := coalesce(nullif(trim(coalesce(g.prenom, '') || ' ' || coalesce(g.nom, '')), ''), 'contact ' || g.id);
  v_lib_d := coalesce(nullif(trim(coalesce(d.prenom, '') || ' ' || coalesce(d.nom, '')), ''), 'contact ' || d.id);

  if g.statut in ('Consultant CDI','Freelance','Prestataire') or d.statut in ('Consultant CDI','Freelance','Prestataire') then
    raise exception 'Fusion refusée : % est % (effectif). Une fiche de l''effectif ne se fusionne pas automatiquement : à traiter à la main par un admin.',
      case when g.statut in ('Consultant CDI','Freelance','Prestataire') then v_lib_g || ' (' || g.id || ')' else v_lib_d || ' (' || d.id || ')' end,
      case when g.statut in ('Consultant CDI','Freelance','Prestataire') then g.statut else d.statut end
      using errcode = 'P0001';
  end if;

  if jules._norm(g.responsable) <> jules._norm(d.responsable) then
    raise exception 'Fusion refusée : les deux fiches n''ont pas le même responsable (% pour %, % pour %). Confie d''abord l''une au responsable de l''autre, puis réessaie.',
      coalesce(g.responsable, 'personne'), g.id, coalesce(d.responsable, 'personne'), d.id using errcode = 'P0001';
  end if;

  -- « Même personne » : même mail, ou (mail vide d'un côté + même prénom et nom + un compte en commun).
  v_mail_g := lower(btrim(coalesce(g.email, '')));
  v_mail_d := lower(btrim(coalesce(d.email, '')));
  if v_mail_g <> '' and v_mail_g = v_mail_d then
    v_critere := 'mail';
  elsif v_mail_g <> '' and v_mail_d <> '' then
    raise exception 'Fusion refusée : les mails diffèrent (% / %). Rien ne prouve que ce soit la même personne.', g.email, d.email
      using errcode = 'P0001';
  else
    if jules._norm(g.prenom) = '' or jules._norm(g.nom) = ''
       or jules._norm(g.prenom) <> jules._norm(d.prenom) or jules._norm(g.nom) <> jules._norm(d.nom) then
      raise exception 'Fusion refusée : pas de mail commun et les noms diffèrent (« % » / « % »). Une seule lettre d''écart suffit à refuser : à trancher à la main.',
        v_lib_g, v_lib_d using errcode = 'P0001';
    end if;
    select a.compte_id into v_compte
      from public.contact_compte a join public.contact_compte b on b.compte_id = a.compte_id
     where a.contact_id = p_garde and b.contact_id = p_doublon and a.date_fin is null and b.date_fin is null
     order by a.compte_id limit 1;
    if v_compte is null then
      raise exception 'Fusion refusée : même nom (« % ») mais pas de mail commun ni de compte rattaché en commun. Peut-être un homonyme : à trancher à la main.',
        v_lib_g using errcode = 'P0001';
    end if;
    v_critere := 'nom+compte';
  end if;

  -- Plafond anti-masse pour Jules (clé service) : 20 fusions par 24 h.
  if v_origine = 'jules' then
    select count(*) into v_n from public.corbeille
     where par_nom = v_nom and liens ? 'fusion' and supprime_le > now() - interval '24 hours';
    if v_n >= 20 then
      raise exception 'Fusion refusée : déjà % fusions ces dernières 24 h (limite 20 pour Jules). Les suivantes attendent demain ou un admin.', v_n
        using errcode = 'P0001';
    end if;
  end if;

  -- b. Photo des deux fiches AVANT toute écriture.
  v_photo := jsonb_build_object('garde', public._fusion_photo(p_garde), 'doublon', public._fusion_photo(p_doublon));

  -- c. Déplacements vers la fiche gardée.
  with m as (update public.historique_actions set id_prospect = p_garde where id_prospect = p_doublon returning id)
  select coalesce(jsonb_agg(id order by id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('historique_actions', v_x);

  with m as (update public.taches set contact_id = p_garde where contact_id = p_doublon returning id)
  select coalesce(jsonb_agg(id order by id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('taches', v_x);

  with m as (update public.session_prospection_contacts x set contact_id = p_garde where x.contact_id = p_doublon and not exists (select 1 from public.session_prospection_contacts y where y.session_id = x.session_id and y.contact_id = p_garde) returning x.id)
  select coalesce(jsonb_agg(id order by id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('session_prospection_contacts', v_x);

  with m as (update jules.alertes_double_contact set contact_id = p_garde where contact_id = p_doublon returning id)
  select coalesce(jsonb_agg(id order by id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('jules.alertes_double_contact', v_x);

  -- db/68 : profils de dossier Jules (jules.profils_mission.crm_contact_id, clé étrangère « on delete set null »).
  -- Recollés à la fiche gardée AVANT la mise en corbeille du doublon : sinon la suppression les détache en silence
  -- et la liste d'appels de Jules recréerait une fiche. Pas d'unicité sur cette colonne : si un dossier avait déjà
  -- un profil sur la fiche gardée, les deux profils pointent la même fiche (signalé, rien n'est supprimé).
  with m as (update jules.profils_mission set crm_contact_id = p_garde where crm_contact_id = p_doublon returning id)
  select coalesce(jsonb_agg(id order by id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('jules.profils_mission', v_x);
  select count(*) into v_n
    from (select mission_id from jules.profils_mission where crm_contact_id = p_garde
           group by mission_id having count(*) > 1) s;
  if v_n > 0 then
    v_signaux := v_signaux || ('La fiche gardée est maintenant reliée à deux profils (ou plus) dans ' || v_n
                               || ' dossier(s) Jules : un profil est en trop dans le dossier, à écarter.');
  end if;

  -- Candidatures : une seule par besoin et par contact. Celle du doublon sur un besoin où la fiche gardée est
  -- déjà candidate reste sur le doublon (elle part en corbeille avec lui).
  with m as (update public.besoin_candidats x set contact_id = p_garde
              where x.contact_id = p_doublon
                and not exists (select 1 from public.besoin_candidats y where y.besoin_id = x.besoin_id and y.contact_id = p_garde)
              returning id)
  select coalesce(jsonb_agg(id order by id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('besoin_candidats', v_x);

  -- Interco : un mois par consultant. Mois en double : on garde celui de la fiche gardée, l'autre est archivé.
  with s as (delete from public.interco_imputations x
              where x.contact_consultant_id = p_doublon
                and exists (select 1 from public.interco_imputations y where y.contact_consultant_id = p_garde and y.annee = x.annee and y.mois = x.mois)
              returning to_jsonb(x.*) j)
  select coalesce(jsonb_agg(j), '[]') into v_supp_interco from s;
  with m as (update public.interco_imputations set contact_consultant_id = p_garde where contact_consultant_id = p_doublon returning id)
  select coalesce(jsonb_agg(id order by id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('interco_imputations', v_x);

  -- Partner : clé (partner, consultant). Même partner des deux côtés : celui du doublon est archivé.
  with s as (delete from public.partner_consultants x
              where x.contact_consultant_id = p_doublon
                and exists (select 1 from public.partner_consultants y where y.contact_consultant_id = p_garde and y.partner_id = x.partner_id)
              returning to_jsonb(x.*) j)
  select coalesce(jsonb_agg(j), '[]') into v_supp_partner from s;
  with m as (update public.partner_consultants set contact_consultant_id = p_garde where contact_consultant_id = p_doublon returning partner_id)
  select coalesce(jsonb_agg(partner_id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('partner_consultants', v_x);

  -- Besoins et missions : chaque colonne qui cite le doublon.
  with m as (update public.besoins set contact_id = p_garde where contact_id = p_doublon returning jsonb_build_object('id', id, 'col', 'contact_id') j)
  select coalesce(jsonb_agg(j), '[]') into v_x from m;
  with m as (update public.besoins set candidat_id = p_garde where candidat_id = p_doublon returning jsonb_build_object('id', id, 'col', 'candidat_id') j)
  select v_x || coalesce(jsonb_agg(j), '[]') into v_x from m;
  with m as (update public.besoins set consultant_id = p_garde where consultant_id = p_doublon returning jsonb_build_object('id', id, 'col', 'consultant_id') j)
  select v_x || coalesce(jsonb_agg(j), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('besoins', v_x);

  with m as (update public.missions set contact_consultant_id = p_garde where contact_consultant_id = p_doublon returning jsonb_build_object('id', id, 'col', 'contact_consultant_id') j)
  select coalesce(jsonb_agg(j), '[]') into v_x from m;
  with m as (update public.missions set contact_referent_id = p_garde where contact_referent_id = p_doublon returning jsonb_build_object('id', id, 'col', 'contact_referent_id') j)
  select v_x || coalesce(jsonb_agg(j), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('missions', v_x);

  -- Séquences de Jules : contact_id, et la cible « contact_crm » quand elle porte l'id du doublon (sauf si la fiche
  -- gardée est déjà ciblée dans la même campagne : unicité mission + cible).
  with m as (update jules.agent_sequences set contact_id = p_garde where contact_id = p_doublon returning id, target_ref)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'target_ref', target_ref) order by id), '[]') into v_x from m;
  with t as (update jules.agent_sequences s set target_ref = p_garde::text
              where s.id in (select (e ->> 'id')::uuid from jsonb_array_elements(v_x) e)
                and s.target_kind = 'contact_crm' and s.target_ref = p_doublon::text
                and not exists (select 1 from jules.agent_sequences o
                                 where o.mission_id is not distinct from s.mission_id and o.target_kind = 'contact_crm'
                                   and o.target_ref = p_garde::text and o.id <> s.id)
              returning s.id)
  select coalesce(jsonb_agg(e || jsonb_build_object('cible_changee', (e ->> 'id')::uuid in (select id from t))), '[]') into v_x
    from jsonb_array_elements(v_x) e;
  v_dep := v_dep || jsonb_build_object('jules.agent_sequences', v_x);
  select count(*) into v_n
    from jules.agent_sequences a join jules.agent_sequences b on b.mission_id = a.mission_id and b.id < a.id
   where a.contact_id = p_garde and b.contact_id = p_garde and a.statut in ('active','paused') and b.statut in ('active','paused');
  if v_n > 0 then
    v_signaux := v_signaux || ('La fiche gardée a maintenant ' || (v_n + 1) || ' séquences Jules en cours dans une même campagne : vérifier qu''elle ne sera pas contactée deux fois.');
  end if;

  -- Liens comptes : déplacés sauf vers un compte déjà relié à la fiche gardée (unicité contact + compte).
  with m as (update public.contact_compte x set contact_id = p_garde
              where x.contact_id = p_doublon
                and not exists (select 1 from public.contact_compte y where y.contact_id = p_garde and y.compte_id = x.compte_id)
              returning id, is_primary)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'is_primary', is_primary) order by id), '[]') into v_x from m;
  -- Un seul compte principal : si la fiche gardée en avait déjà un, les liens arrivés ne le sont plus.
  if exists (select 1 from public.contact_compte y
              where y.contact_id = p_garde and y.is_primary and y.date_fin is null
                and y.id not in (select (e ->> 'id')::bigint from jsonb_array_elements(v_x) e)) then
    update public.contact_compte set is_primary = false
     where id in (select (e ->> 'id')::bigint from jsonb_array_elements(v_x) e) and is_primary;
  end if;
  v_dep := v_dep || jsonb_build_object('contact_compte', v_x);
  if exists (select 1 from public.contact_compte a join public.contact_compte b on b.compte_id = a.compte_id
              where a.contact_id = p_doublon and a.date_fin is null and b.contact_id = p_garde and b.date_fin is not null) then
    v_signaux := v_signaux || 'Le doublon était encore rattaché à un compte dont la fiche gardée est sortie (lien clos) : le lien clos est gardé, à vérifier.'::text;
  end if;

  -- besoins_statuts (ancien suivi, clé texte) : déplacé seulement si la fiche gardée n'en a pas.
  if exists (select 1 from public.besoins_statuts where contact_id = p_doublon::text) then
    if exists (select 1 from public.besoins_statuts where contact_id = p_garde::text) then
      v_signaux := v_signaux || 'Les deux fiches avaient un suivi besoins_statuts : celui du doublon est laissé tel quel (à relire).'::text;
      v_dep := v_dep || jsonb_build_object('besoins_statuts', false);
    else
      update public.besoins_statuts set contact_id = p_garde::text where contact_id = p_doublon::text;
      v_dep := v_dep || jsonb_build_object('besoins_statuts', true);
    end if;
  end if;

  -- Exclusions de partage de compte (tableau d'ids).
  with m as (update jules.partages_compte set contacts_exclus = array_replace(contacts_exclus, p_doublon::int, p_garde::int)
              where p_doublon::int = any (contacts_exclus) and not (p_garde::int = any (contacts_exclus)) returning id)
  select coalesce(jsonb_agg(id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('partages_remplaces', v_x);
  with m as (update jules.partages_compte set contacts_exclus = array_remove(contacts_exclus, p_doublon::int)
              where p_doublon::int = any (contacts_exclus) returning id)
  select coalesce(jsonb_agg(id), '[]') into v_x from m;
  v_dep := v_dep || jsonb_build_object('partages_retires', v_x);

  -- d. Champs vides de la fiche gardée complétés par ceux du doublon (jamais d'écrasement).
  v_gj := to_jsonb(g);
  v_dj := to_jsonb(d);
  foreach v_col in array array['email','telephone','linkedin','role','ville','employeur','agence','ats','besoins','commentaires','date_premier'] loop
    if coalesce(btrim(v_gj ->> v_col), '') = '' and coalesce(btrim(v_dj ->> v_col), '') <> '' then
      execute format('update public.contacts c set %1$I = (jsonb_populate_record(c, $1)).%1$I where c.id = $2', v_col)
        using jsonb_build_object(v_col, v_dj -> v_col), p_garde;
      v_champs := v_champs || jsonb_build_object(v_col, jsonb_build_object('avant', v_gj -> v_col, 'apres', v_dj -> v_col));
    end if;
  end loop;

  if coalesce(d.ne_pas_recontacter, false) and not coalesce(g.ne_pas_recontacter, false) then
    v_signaux := v_signaux || ('Le doublon était marqué « Ne pas recontacter » (' || coalesce(d.ne_pas_recontacter_note, 'sans note') || '), pas la fiche gardée : à vérifier.');
  end if;
  if g.statut is distinct from d.statut then
    v_signaux := v_signaux || ('Statuts différents (' || coalesce(g.statut, 'aucun') || ' gardé, ' || coalesce(d.statut, 'aucun') || ' sur le doublon).');
  end if;
  if g.etape_prospect is distinct from d.etape_prospect and d.etape_prospect is not null then
    v_signaux := v_signaux || ('Étapes prospect différentes (' || coalesce(g.etape_prospect, 'aucune') || ' gardée, ' || d.etape_prospect || ' sur le doublon).');
  end if;

  -- e. Doublon en corbeille par le chemin habituel (il n'a plus de lien bloquant).
  v_res := public.supprimer_fiche('contact', p_doublon::text,
             'Fusion dans la fiche ' || p_garde || ' (' || v_lib_g || ')' || coalesce(' : ' || v_motif, ''),
             v_origine, false);
  v_arch := (v_res ->> 'archive_id')::bigint;
  if v_arch is null then
    raise exception 'Fusion non faite : la mise en corbeille du doublon n''a pas renvoyé de n° d''archive.' using errcode = 'P0001';
  end if;

  -- Comptes par table (pour la note et le JSON).
  for v_k in select jsonb_object_keys(v_dep) loop
    if jsonb_typeof(v_dep -> v_k) = 'array' and jsonb_array_length(v_dep -> v_k) > 0 then
      v_comptes := v_comptes || jsonb_build_object(v_k, jsonb_array_length(v_dep -> v_k));
    elsif v_dep -> v_k = 'true'::jsonb then
      v_comptes := v_comptes || jsonb_build_object(v_k, 1);
    end if;
  end loop;
  select liens into v_liens from public.corbeille where id = v_arch;
  for v_k in select jsonb_object_keys(v_liens) loop
    if jsonb_typeof(v_liens -> v_k) = 'array' and jsonb_array_length(v_liens -> v_k) > 0 then
      v_laisses := v_laisses || jsonb_build_object(v_k, jsonb_array_length(v_liens -> v_k));
    end if;
  end loop;
  if jsonb_array_length(v_supp_interco) > 0 then v_laisses := v_laisses || jsonb_build_object('interco_imputations', jsonb_array_length(v_supp_interco)); end if;
  if jsonb_array_length(v_supp_partner) > 0 then v_laisses := v_laisses || jsonb_build_object('partner_consultants', jsonb_array_length(v_supp_partner)); end if;

  select coalesce(string_agg(value || ' ' || case key
           when 'historique_actions' then 'action(s) d''historique'
           when 'taches' then 'tâche(s)'
           when 'contact_compte' then 'lien(s) compte'
           when 'besoin_candidats' then 'candidature(s)'
           when 'besoins' then 'besoin(s)'
           when 'missions' then 'mission(s)'
           when 'session_prospection_contacts' then 'ligne(s) de session de prospection'
           when 'jules.agent_sequences' then 'séquence(s) Jules'
           when 'jules.alertes_double_contact' then 'alerte(s) double contact'
           when 'jules.profils_mission' then 'profil(s) de dossier Jules'
           when 'interco_imputations' then 'imputation(s) interco'
           when 'partner_consultants' then 'rattachement(s) partner'
           when 'besoins_statuts' then 'suivi besoins_statuts'
           when 'partages_remplaces' then 'exclusion(s) de partage'
           when 'partages_retires' then 'exclusion(s) de partage en double retirée(s)'
           else key end, ', ' order by key), 'rien')
    into v_resume from jsonb_each_text(v_comptes);

  -- f. Note de fusion sur la fiche gardée, puis date du dernier échange recalculée (la note n'est pas un échange).
  insert into public.historique_actions (id_prospect, date, type_action, details, responsable)
  values (p_garde, current_date, 'Note interne',
          'Fusion du contact ' || p_doublon || ' (' || v_lib_d || ') dans cette fiche, corbeille n° ' || v_arch
          || ' (critère : ' || case v_critere when 'mail' then 'même mail' else 'même nom et même compte' end || '). Déplacé : ' || v_resume || '.'
          || case when v_champs <> '{}'::jsonb then ' Champs complétés : ' || (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_champs) k) || '.' else '' end
          || coalesce(' Motif : ' || v_motif || '.', ''),
          v_nom)
  returning id into v_trace;
  update public.contacts
     set date_dernier = (select max(x) from (values (g.date_dernier), (d.date_dernier)) v(x)),
         updated_at = now()
   where id = p_garde;

  -- Bloc « fusion » dans l'archive du doublon (de quoi la défaire avec restaurer_fiche).
  update public.corbeille
     set liens = jsonb_set(jsonb_set(liens,
                   '{interco_imputations}', coalesce(liens -> 'interco_imputations', '[]') || v_supp_interco),
                   '{partner_consultants}', coalesce(liens -> 'partner_consultants', '[]') || v_supp_partner)
                 || jsonb_build_object('fusion', jsonb_build_object(
                      'version', 1, 'garde', p_garde, 'doublon', p_doublon, 'critere', v_critere,
                      'deplaces', v_dep, 'champs_completes', v_champs, 'trace_id', v_trace,
                      'garde_avant', jsonb_build_object('date_dernier', g.date_dernier, 'updated_at', g.updated_at),
                      'signaux', to_jsonb(v_signaux), 'par', v_nom, 'le', now(),
                      'photo', v_photo))
   where id = v_arch;

  -- g. Résultat.
  return jsonb_build_object(
    'garde', p_garde, 'garde_libelle', v_lib_g,
    'doublon', p_doublon, 'doublon_libelle', v_lib_d,
    'critere', v_critere,
    'archive_id', v_arch,
    'deplaces', v_comptes,
    'laisses_en_corbeille', v_laisses,
    'champs_completes', (select coalesce(jsonb_object_agg(k, v -> 'apres'), '{}') from jsonb_each(v_champs) e(k, v)),
    'signaux', to_jsonb(v_signaux),
    'trace_id', v_trace,
    'par', v_nom);
end;
$function$
;

CREATE OR REPLACE FUNCTION public._fusion_photo(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'ligne',                (select to_jsonb(c.*) from public.contacts c where c.id = p_id),
    'contact_compte',       (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.contact_compte x where x.contact_id = p_id),
    'taches',               (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.taches x where x.contact_id = p_id),
    'historique_actions',   (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.historique_actions x where x.id_prospect = p_id),
    'besoin_candidats',     (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.besoin_candidats x where x.contact_id = p_id),
    'session_prospection_contacts', (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.session_prospection_contacts x where x.contact_id = p_id),
    'interco_imputations',  (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.interco_imputations x where x.contact_consultant_id = p_id),
    'partner_consultants',  (select coalesce(jsonb_agg(to_jsonb(x.*)), '[]') from public.partner_consultants x where x.contact_consultant_id = p_id),
    'besoins',              (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'contact_id', b.contact_id, 'candidat_id', b.candidat_id, 'consultant_id', b.consultant_id) order by b.id), '[]')
                               from public.besoins b where p_id in (b.contact_id, b.candidat_id, b.consultant_id)),
    'missions',             (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'contact_consultant_id', m.contact_consultant_id, 'contact_referent_id', m.contact_referent_id) order by m.id), '[]')
                               from public.missions m where p_id in (m.contact_consultant_id, m.contact_referent_id)),
    'agent_sequences',      (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from jules.agent_sequences x where x.contact_id = p_id),
    'alertes_double_contact', (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.created_at), '[]') from jules.alertes_double_contact x where x.contact_id = p_id),
    'besoins_statuts',      (select coalesce(jsonb_agg(to_jsonb(x.*)), '[]') from public.besoins_statuts x where x.contact_id = p_id::text),
    'partages_compte',      (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'contacts_exclus', x.contacts_exclus)), '[]')
                               from jules.partages_compte x where p_id::int = any (x.contacts_exclus)),
    -- db/68 : profils de dossier Jules reliés à la fiche (identifiants seulement : les lignes sont lourdes).
    'profils_mission',      (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'mission_id', x.mission_id, 'nom', x.nom, 'statut', x.statut) order by x.id), '[]')
                               from jules.profils_mission x where x.crm_contact_id = p_id)
  )
$function$
;

CREATE OR REPLACE FUNCTION public._fusion_defaire(p_f jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  g bigint := (p_f ->> 'garde')::bigint;
  d bigint := (p_f ->> 'doublon')::bigint;
  v_dep jsonb := coalesce(p_f -> 'deplaces', '{}'::jsonb);
  n_ok int := 0;
  v_ign jsonb := '[]'::jsonb;
  v_n int;
  v_t record;
  v_e jsonb;
  v_k text; v_v jsonb;
begin
  -- Tables à clé « id » : la ligne revient au doublon si elle est toujours sur la fiche gardée.
  for v_t in select * from (values
      ('historique_actions', 'public.historique_actions', 'id_prospect'),
      ('taches', 'public.taches', 'contact_id'),
      ('session_prospection_contacts', 'public.session_prospection_contacts', 'contact_id'),
      ('jules.alertes_double_contact', 'jules.alertes_double_contact', 'contact_id'),
      ('besoin_candidats', 'public.besoin_candidats', 'contact_id'),
      ('interco_imputations', 'public.interco_imputations', 'contact_consultant_id'),
      ('contact_compte', 'public.contact_compte', 'contact_id'),
      ('jules.agent_sequences', 'jules.agent_sequences', 'contact_id'),
      ('jules.profils_mission', 'jules.profils_mission', 'crm_contact_id')) t(cle, tab, col)   -- db/68
  loop
    for v_e in select jsonb_array_elements(coalesce(v_dep -> v_t.cle, '[]'::jsonb)) loop
      begin
        execute format('update %s set %I = $1 where id::text = $2 and %I = $3', v_t.tab, v_t.col, v_t.col)
          using d, case when jsonb_typeof(v_e) = 'object' then v_e ->> 'id' else v_e #>> '{}' end, g;
        get diagnostics v_n = row_count;
      exception when others then v_n := 0;
      end;
      if v_n = 1 then
        n_ok := n_ok + 1;
        if v_t.cle = 'contact_compte' then
          update public.contact_compte set is_primary = (v_e ->> 'is_primary')::boolean where id = (v_e ->> 'id')::bigint;
        elsif v_t.cle = 'jules.agent_sequences' and coalesce((v_e ->> 'cible_changee')::boolean, false) then
          update jules.agent_sequences set target_ref = v_e ->> 'target_ref' where id = (v_e ->> 'id')::uuid;
        end if;
      else
        v_ign := v_ign || jsonb_build_object('table', v_t.cle, 'id', case when jsonb_typeof(v_e) = 'object' then v_e ->> 'id' else v_e #>> '{}' end,
                                             'raison', 'ligne supprimée ou déplacée depuis la fusion');
      end if;
    end loop;
  end loop;

  -- Partner (clé partner + consultant).
  for v_e in select jsonb_array_elements(coalesce(v_dep -> 'partner_consultants', '[]'::jsonb)) loop
    begin
      update public.partner_consultants set contact_consultant_id = d
       where partner_id = (v_e #>> '{}')::uuid and contact_consultant_id = g;
      get diagnostics v_n = row_count;
    exception when others then v_n := 0;
    end;
    if v_n = 1 then n_ok := n_ok + 1;
    else v_ign := v_ign || jsonb_build_object('table', 'partner_consultants', 'id', v_e #>> '{}', 'raison', 'lien absent'); end if;
  end loop;

  -- Besoins et missions : colonne par colonne.
  for v_k in select unnest(array['besoins','missions']) loop
    for v_e in select jsonb_array_elements(coalesce(v_dep -> v_k, '[]'::jsonb)) loop
      execute format('update public.%I set %I = $1 where id::text = $2 and %I = $3', v_k, v_e ->> 'col', v_e ->> 'col')
        using d, v_e ->> 'id', g;
      get diagnostics v_n = row_count;
      if v_n = 1 then n_ok := n_ok + 1;
      else v_ign := v_ign || jsonb_build_object('table', v_k, 'id', v_e ->> 'id', 'raison', (v_e ->> 'col') || ' modifié depuis la fusion'); end if;
    end loop;
  end loop;

  if coalesce((v_dep ->> 'besoins_statuts')::boolean, false) then
    update public.besoins_statuts set contact_id = d::text where contact_id = g::text;
    get diagnostics v_n = row_count;
    n_ok := n_ok + v_n;
  end if;
  update jules.partages_compte set contacts_exclus = array_replace(contacts_exclus, g::int, d::int)
   where id in (select (e #>> '{}')::uuid from jsonb_array_elements(coalesce(v_dep -> 'partages_remplaces', '[]')) e)
     and g::int = any (contacts_exclus);
  update jules.partages_compte set contacts_exclus = array_append(contacts_exclus, d::int)
   where id in (select (e #>> '{}')::uuid from jsonb_array_elements(coalesce(v_dep -> 'partages_retires', '[]')) e)
     and not (d::int = any (contacts_exclus));

  -- Champs complétés : vidés seulement s'ils portent encore la valeur venue du doublon.
  for v_k, v_v in select key, value from jsonb_each(coalesce(p_f -> 'champs_completes', '{}'::jsonb)) loop
    execute format('update public.contacts c set %1$I = (jsonb_populate_record(c, $1)).%1$I where c.id = $2 and to_jsonb(c) -> %2$L = $3', v_k, v_k)
      using jsonb_build_object(v_k, v_v -> 'avant'), g, v_v -> 'apres';
    get diagnostics v_n = row_count;
    if v_n = 1 then n_ok := n_ok + 1;
    else v_ign := v_ign || jsonb_build_object('table', 'contacts', 'id', g::text, 'raison', 'champ ' || v_k || ' retouché depuis la fusion : laissé tel quel'); end if;
  end loop;

  -- Note de fusion retirée, dates de la fiche gardée remises.
  delete from public.historique_actions where id = (p_f ->> 'trace_id')::int and id_prospect = g;
  update public.contacts
     set date_dernier = (p_f #>> '{garde_avant,date_dernier}')::timestamptz,
         updated_at   = (p_f #>> '{garde_avant,updated_at}')::timestamptz
   where id = g;

  return jsonb_build_object('lignes', n_ok, 'ignorees', v_ign);
end;
$function$
;


-- A9. Contrôles avant commit : marques 68 présentes, droits inchangés, SECURITY DEFINER + search_path fixé.
do $$
declare r record;
begin
  for r in select p.proname, p.prosecdef, p.proconfig, p.prosrc ~ 'db/68' m68 from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('fusionner_contacts','_fusion_photo','_fusion_defaire') loop
    if not r.m68 then raise exception 'db/68 : % non remplacée', r.proname; end if;
    if not r.prosecdef or r.proconfig is null or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
      raise exception 'db/68 : % doit rester SECURITY DEFINER avec search_path fixé', r.proname;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'public.fusionner_contacts(bigint,bigint,text,text)', 'execute')
     or not has_function_privilege('service_role', 'public.fusionner_contacts(bigint,bigint,text,text)', 'execute') then
    raise exception 'db/68 : fusionner_contacts doit rester exécutable par authenticated et service_role';
  end if;
  if has_function_privilege('authenticated', 'public._fusion_defaire(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public._fusion_photo(bigint)', 'execute') then
    raise exception 'db/68 : les fonctions internes ne doivent pas être ouvertes à authenticated';
  end if;
  raise notice 'db/68 appliquée : la fusion recolle jules.profils_mission.';
end $$;

notify pgrst, 'reload schema';
commit;
