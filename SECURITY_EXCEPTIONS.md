# Exceptions de sécurité documentées (Terraform)

Ce fichier liste les findings remontés par `tfsec`/`checkov` sur le code Terraform
qui n'ont **pas** été corrigés, avec la justification du choix. En sécurité, la bonne
pratique n'est pas de corriger aveuglément 100% des alertes d'un scanner : c'est
d'évaluer chaque finding, corriger ce qui a un vrai impact, et documenter
explicitement ce qu'on accepte et pourquoi — pour que la décision soit tracée et
relue par quelqu'un d'autre, plutôt que silencieusement ignorée.

## Corrigés (voir terraform/environments/dev/main.tf)
- Logs d'audit du control plane EKS (`aws-eks-enable-control-plane-logging`)
- VPC Flow Logs (`aws-ec2-require-vpc-flow-logs-for-all-vpcs`)
- Chiffrement KMS dédié pour l'état Terraform et la table de verrouillage (S3/DynamoDB)
- Point-in-time recovery sur la table DynamoDB de verrouillage
- Modules Terraform épinglés à une version exacte plutôt qu'une contrainte ouverte (`CKV_TF_1`)

## Acceptés (avec justification)

| Finding | Sévérité | Justification |
|---|---|---|
| `aws-eks-no-public-cluster-access` (accès public au cluster) | CRITICAL | L'accès public est restreint à une seule IP explicite (`admin_cidr_blocks`), pas ouvert à Internet. Un accès purement privé demanderait un VPN/bastion, hors budget de ce projet de démonstration. Le risque réel (accès non autorisé) est mitigé par la restriction CIDR, pas éliminé par principe. |
| Security group : egress vers `0.0.0.0/0` | CRITICAL | Nécessaire pour que les nœuds/pods atteignent Internet (tirer les images de base Python, appeler les APIs AWS) via la NAT Gateway. Une alternative plus stricte existerait (VPC endpoints pour ECR/S3/STS, supprimant tout besoin d'egress internet), documentée ici comme piste d'amélioration plutôt qu'implémentée, pour limiter la complexité d'un environnement de démonstration à courte durée de vie. |
| Network ACL permissive (ALL ports, ingress public) | CRITICAL (x6) | Il s'agit du NACL par défaut créé par AWS/le module VPC. C'est le modèle de sécurité recommandé par AWS lui-même : les Security Groups (avec état, attachés par ressource) sont la limite de sécurité principale ; les NACL (sans état, au niveau du sous-réseau) sont une couche secondaire souvent laissée permissive par design pour éviter de dupliquer/complexifier la logique de filtrage. Durcir les NACL est une option de renforcement supplémentaire, pas une lacune de sécurité de base. |
| Chiffrement ECR sans clé KMS dédiée | LOW | Le chiffrement est actif (AWS KMS géré par AWS). Une clé dédiée apporterait un contrôle plus fin (rotation, révocation, politique d'accès) mais ajoute de la complexité pour un bénéfice marginal ici — le contenu (une image d'une app de démo sans secret) ne le justifie pas. |
| Bucket S3 (état Terraform) sans logging d'accès activé | MEDIUM | Ajouter le logging demanderait un second bucket S3 dédié aux logs. Le bucket contient l'état d'une infrastructure de démonstration détruite en fin de test — le rapport coût/bénéfice ne justifie pas cette complexité supplémentaire ici, mais serait fait sans hésiter pour un état Terraform de production de longue durée.

| Image de conteneur référencée par tag et non par digest sha256 (`CKV_K8S_43`) | MEDIUM | Le dépôt ECR est configuré en `image_tag_mutability = IMMUTABLE` (voir terraform/environments/dev/main.tf) : une fois poussé, un tag ne peut plus jamais être réécrit pour pointer vers un autre contenu. L'essentiel de la garantie recherchée par un digest (immutabilité de ce qui est réellement déployé) est donc déjà obtenue au niveau du registre. Résoudre le digest exact dans le script de déploiement est une amélioration possible, documentée mais non implémentée ici. |

## Comment vérifier soi-même
```bash
tfsec terraform/ --no-color
checkov -d terraform/environments/dev --compact
```
