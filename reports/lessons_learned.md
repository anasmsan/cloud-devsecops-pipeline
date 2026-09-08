# Découvertes réelles faites pendant le déploiement en direct

Ce projet n'a pas été qu'écrit puis supposé fonctionner : il a été **déployé pour
de vrai** sur un compte AWS, ce qui a permis de découvrir deux problèmes réels
qu'aucune revue de code ni aucun `terraform plan` n'auraient révélés.

## 1. Les NetworkPolicy n'étaient pas appliquées par défaut sur EKS

**Constat :** après le premier déploiement, un pod de test placé dans un autre
namespace arrivait quand même à joindre le service `demo-service`, alors qu'une
`NetworkPolicy` de refus par défaut (`k8s/base/networkpolicy.yaml`) était bien
présente et acceptée par l'API Kubernetes (`kubectl get networkpolicy` la
listait normalement).

**Cause :** le CNI par défaut d'EKS (Amazon VPC CNI) n'active pas
l'**application réelle** des NetworkPolicy tant que l'option
`enableNetworkPolicy` n'est pas explicitement activée sur l'add-on `vpc-cni`.
Sans elle, les objets `NetworkPolicy` sont acceptés par l'API Kubernetes
(aucune erreur, aucun avertissement) mais n'ont strictement aucun effet — un
piège silencieux particulièrement dangereux : on peut légitimement croire son
cluster isolé alors qu'il ne l'est pas du tout.

**Correction :** ajout d'un bloc `cluster_addons` dans
`terraform/environments/dev/main.tf` configurant explicitement `vpc-cni` avec
`enableNetworkPolicy = "true"`. Après application et redéploiement de l'add-on,
le même test de pod inter-namespace a échoué en timeout, confirmant
l'isolation réelle — et un test positif (accès autorisé depuis le bon chemin)
a été vérifié via `kubectl port-forward`.

**À retenir :** ne jamais faire confiance à la simple présence d'un objet
`NetworkPolicy` dans le cluster comme preuve d'isolation réseau — il faut
**tester activement** qu'elle bloque bien ce qu'elle est censée bloquer,
exactement comme on teste une règle de pare-feu.

## 2. `docker buildx` génère un index multi-plateforme même pour une seule architecture

**Constat :** le scan de vulnérabilités automatique d'ECR (`scan_on_push`)
n'a jamais démarré sur l'image poussée, malgré une configuration correcte du
dépôt (`image_scanning_configuration.scan_on_push = true`, vérifié via
`aws ecr describe-repositories`).

**Cause :** `docker buildx build` génère par défaut un **index d'image OCI**
(`application/vnd.oci.image.index.v1+json`) contenant à la fois l'image et une
attestation de provenance, même en ciblant une seule plateforme
(`--platform linux/amd64`). Le scan basique d'ECR ne sait analyser qu'un
manifeste d'image simple, pas un index — confirmé via
`aws ecr describe-images`, qui affichait exactement ce type de manifeste pour
le tag concerné.

**Correction documentée (non réappliquée pour limiter la durée du test) :**
ajouter `--provenance=false` à la commande `docker buildx build` pour forcer
la génération d'un manifeste d'image simple, scannable par ECR.

**À retenir :** un scan de sécurité configuré "correctement" sur le papier
peut ne jamais s'exécuter à cause d'un détail de format d'image — vérifier
qu'un scan a réellement tourné (`describe-image-scan-findings`), pas
seulement que l'option qui est censée le déclencher est activée.

## Pourquoi documenter ces deux ratés plutôt que les cacher

En entretien, savoir raconter ce qui n'a **pas** marché du premier coup — et
comment on l'a diagnostiqué puis corrigé — est un bien meilleur signal que de
prétendre que tout a fonctionné dès la première tentative. C'est aussi
exactement le travail réel d'un ingénieur DevSecOps : la sécurité "sur le
papier" (code review, scan statique) ne remplace jamais la vérification en
conditions réelles.
