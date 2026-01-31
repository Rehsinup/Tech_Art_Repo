using UnityEngine;

public class GroundSlashShooter : MonoBehaviour
{
    public Camera cam;
    [SerializeField] GameObject projectile;
    public Transform firePoint;
    public float fireRate = 4;

    private Vector3 destination;
    private float timeToFire;
    private GroundSlash slashscript;


    private void Start()
    {
        slashscript = GetComponent<GroundSlash>();
    }

    void Update()
    {
        if (Input.GetButton("Fire1") && Time.time >= timeToFire)
        {
            timeToFire = Time.time + 1 / fireRate;
            ShootProjectile();
        }
    }

    void ShootProjectile()
    {
        Ray ray = cam.ViewportPointToRay(new Vector3(0.5f, 0.5f, 0));
       destination = ray.GetPoint(1000);
    
        InstantiateProjectile();
    }

    void InstantiateProjectile()
    {
       var projectileObj = Instantiate(projectile, firePoint.position, Quaternion.identity) as GameObject;
       slashscript = projectileObj.GetComponent<GroundSlash>();
        RotationToDestination(projectileObj, destination, true);
       projectileObj.GetComponent<Rigidbody>().linearVelocity = transform.forward * slashscript.speed;
    }

    void RotationToDestination(GameObject obj, Vector3 destination, bool OnlyY)
    {
        var direction = destination - obj.transform.position;
        var rotation = Quaternion.LookRotation(direction);
    
        if (OnlyY)
        {
            rotation.x = 0;
            rotation.z = 0;
        }
        obj.transform.localRotation = Quaternion.Lerp(obj.transform.localRotation, rotation, 1);
    }
}
